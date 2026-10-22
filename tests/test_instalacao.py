"""Bootstrap em cópias descartáveis: falhas simuladas e fluxo real sem DATASUS."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


RAIZ = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")
RSCRIPT = shutil.which("Rscript")


def copiar_projeto(destino):
    arquivos = ["app.py", "configurar.sh", "iniciar.sh", "scripts/ambiente.sh",
        "scripts/gerar_referencia_cid10.py", "R/configurar_ambiente.R", "R/coletar_dados.R",
        "R/sistemas/sim.R", "R/comum/cid.R", "R/comum/auditoria.R", "R/comum/exportacao.R",
        "referencias/cid10/oms_2019_codigos.json", "referencias/cid10/icd102019en.xml.zip", "Dados/.gitkeep"]
    for nome in arquivos:
        p = destino / nome
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(RAIZ / nome, p)
    (destino / "Dados/anterior").mkdir()
    (destino / "Dados/anterior/sintetico.csv").write_text('campo\n"dado sintético preservado"\n', encoding="utf-8")


def snapshot(pasta):
    return {str(p.relative_to(pasta)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in pasta.rglob("*") if p.is_file()}


class TestScriptsInstalacao(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="import-mds-instalar-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.projeto = self.base / "Projeto com espaços ' [a] $HOME ;"
        copiar_projeto(self.projeto)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for cmd in ["readlink", "dirname", "uname", "sha256sum", "mktemp", "ln", "rm", "rmdir", "mkdir"]:
            os.symlink(shutil.which(cmd), self.bin / cmd)
        os.symlink(sys.executable, self.bin / "python3")
        self.executavel("R", "exit 0")
        self.executavel("Rscript", r'''
if [[ ${1-} == --vanilla && ${2-} == */R/configurar_ambiente.R ]]; then
    case "${3-}" in
        biblioteca)
            if [[ ${FALHA_R_VERSAO:-0} == 1 ]]; then echo 'ERRO: R 4.1.0 ou superior é necessário.' >&2; exit 1; fi
            printf '%s/.biblioteca-R/simulada' "$4" ;;
        verificar)
            echo verificar >> "$EVENTOS"
            if [[ ${FALTA_PACOTE:-0} == 1 && ! -f "$INSTALADO" ]]; then
                echo 'ATENÇÃO: jsonlite ausente ou incompatível; requerido 2.0.0.'; exit 10
            fi
            echo 'Pacotes simulados compatíveis.' ;;
        instalar)
            [[ ${5-} == --confirmado ]] || exit 99
            echo instalar >> "$EVENTOS"
            if [[ ${FALHA_INSTALACAO:-0} == 1 ]]; then echo 'ERRO: falha simulada de instalação da biblioteca.' >&2; exit 1; fi
            printf pronto > "$INSTALADO" ;;
        *) exit 98 ;;
    esac
else
    echo coleta_simulada >> "$EVENTOS"
    printf '%s\n' "$@" > "$ARGUMENTOS"
    echo 'ERRO controlado do subprocesso R simulado; sem acesso ao DATASUS.' >&2
    exit "${CODIGO_COLETA:-7}"
fi
''')
        self.env = os.environ.copy()
        self.env.update(PATH=str(self.bin), EVENTOS=str(self.base / "eventos"),
            INSTALADO=str(self.base / "instalado"), ARGUMENTOS=str(self.base / "argumentos"),
            PYTHONDONTWRITEBYTECODE="1")
        self.env.pop("R_LIBS", None)

    def executavel(self, nome, codigo):
        p = self.bin / nome
        if p.is_symlink():
            p.unlink()
        p.write_text("#!/bin/bash\nset -eu\n" + codigo + "\n", encoding="utf-8")
        p.chmod(0o755)

    def executar(self, script="configurar.sh", argumentos=(), entrada="", env=None):
        return subprocess.run([BASH, str(self.projeto / script), *argumentos], input=entrada,
            text=True, capture_output=True, cwd=self.base, env=env or self.env, timeout=60)

    def eventos(self):
        p = self.base / "eventos"
        return p.read_text().splitlines() if p.exists() else []

    def test_configuracao_idempotente_sem_instalacao(self):
        antes = snapshot(self.projeto)
        for _ in range(2):
            r = self.executar()
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("bash iniciar.sh", r.stdout)
        self.assertNotIn("instalar", self.eventos())
        self.assertNotIn("coleta_simulada", self.eventos())
        self.assertEqual(snapshot(self.projeto), antes)

    def test_check_sem_efeitos_colaterais(self):
        antes = snapshot(self.projeto)
        r = self.executar(argumentos=["--check"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("hard links não são ensaiados", r.stdout)
        self.assertEqual(snapshot(self.projeto), antes)
        self.assertFalse((self.projeto / ".biblioteca-R").exists())
        self.assertNotIn("instalar", self.eventos())

    def test_python_ausente(self):
        (self.bin / "python3").unlink()
        r = self.executar()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("python3 não encontrado", r.stderr)
        self.assertEqual(self.eventos(), [])

    def test_rscript_ausente(self):
        (self.bin / "Rscript").unlink()
        r = self.executar()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Rscript não encontrado", r.stderr)
        self.assertEqual(self.eventos(), [])

    def test_versoes_incompativeis(self):
        self.env["FALHA_R_VERSAO"] = "1"
        r = self.executar()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("R 4.1.0", r.stderr)
        self.assertNotIn("instalar", self.eventos())
        self.executavel("python3", "exit 1")
        r = self.executar()
        self.assertIn("Python 3.8", r.stderr)

    def test_pacote_ausente_check_nao_oferece_instalacao(self):
        self.env["FALTA_PACOTE"] = "1"
        r = self.executar(argumentos=["--check"], entrada="s\n")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("jsonlite", r.stdout)
        self.assertNotIn("instalar", self.eventos())

    def test_recusa_e_entrada_vazia_nao_instalam(self):
        self.env["FALTA_PACOTE"] = "1"
        for entrada in ["n\n", "", "sim-nao\n"]:
            r = self.executar(entrada=entrada)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("não autorizada", r.stderr)
        self.assertNotIn("instalar", self.eventos())

    def test_instalacao_apenas_apos_consentimento_e_reverificacao(self):
        self.env["FALTA_PACOTE"] = "1"
        r = self.executar(entrada="s\n")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.eventos(), ["verificar", "instalar", "verificar"])
        self.assertIn("somente em:", r.stdout)
        r = self.executar()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.eventos().count("instalar"), 1)
        self.assertNotIn("coleta_simulada", self.eventos())

    def test_falha_instalacao_propaga_erro_sem_sucesso(self):
        self.env.update(FALTA_PACOTE="1", FALHA_INSTALACAO="1")
        r = self.executar(entrada="s\n")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("falha simulada", r.stderr)
        self.assertNotIn("Configuração verificada com sucesso", r.stdout)

    def test_inicio_nao_instala_quando_falta_pacote(self):
        self.env["FALTA_PACOTE"] = "1"
        r = self.executar("iniciar.sh", entrada="s\n")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("bash configurar.sh", r.stderr)
        self.assertNotIn("instalar", self.eventos())
        self.assertNotIn("coleta_simulada", self.eventos())

    def test_inicio_menu_real_argumentos_e_codigo_r_simulado(self):
        antes = snapshot(self.projeto)
        self.env["CODIGO_COLETA"] = "23"
        r = self.executar("iniciar.sh", entrada="1\n1\n2014\n2014\nMA\n3\n6\n18\n\nE10-E14\n")
        self.assertEqual(r.returncode, 23, r.stderr)
        self.assertIn("Tipo de dado:", r.stdout)
        self.assertNotIn("Dados coletados com sucesso", r.stdout)
        args = (self.base / "argumentos").read_text().splitlines()
        self.assertEqual(args[0], str(self.projeto / "R/coletar_dados.R"))
        self.assertEqual(args[args.index("--cid") + 1], "E10-E14")
        self.assertEqual(args[args.index("--idade_min") + 1], "18")
        self.assertNotIn("--idade_max", args)
        self.assertEqual(snapshot(self.projeto), antes)

    def test_referencia_corrompida_impede_inicio(self):
        (self.projeto / "referencias/cid10/oms_2019_codigos.json").write_text("{}")
        r = self.executar("iniciar.sh")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("referência CID-10 local inválida", r.stderr)
        self.assertEqual(self.eventos(), [])

    def test_projeto_incompleto(self):
        (self.projeto / "R/sistemas/sim.R").unlink()
        r = self.executar()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("arquivo fundamental", r.stderr)

    def test_sistema_incompativel(self):
        self.executavel("uname", "echo Darwin")
        r = self.executar()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("somente a Linux", r.stderr)
        self.assertEqual(self.eventos(), [])

    def test_hardlink_indisponivel_limpa_so_temporarios_proprios(self):
        antes = snapshot(self.projeto)
        self.executavel("ln", "exit 1")
        r = self.executar()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("não permite hard links", r.stderr)
        self.assertEqual(snapshot(self.projeto), antes)
        self.assertFalse(list((self.projeto / "Dados").glob(".import-mds-teste.*")))

    def test_caminho_dois_pontos_rejeitado_claramente(self):
        novo = self.base / "projeto:incompativel"
        self.projeto.rename(novo)
        self.projeto = novo
        r = self.executar()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("dois-pontos", r.stderr)

    def test_link_simbolico_para_script_resolve_projeto(self):
        link = self.base / "atalho configurar.sh"
        link.symlink_to(self.projeto / "configurar.sh")
        r = subprocess.run([BASH, str(link), "--check"], cwd=self.base, env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_argumentos_desconhecidos_rejeitados(self):
        for script in ["configurar.sh", "iniciar.sh"]:
            r = self.executar(script, argumentos=["--instalar-tudo"])
            self.assertEqual(r.returncode, 2)

    @unittest.skipIf(os.geteuid() == 0, "Verificação de permissões requer usuário sem root")
    def test_permissao_insuficiente(self):
        dados = self.projeto / "Dados"
        dados.chmod(0o500)
        try:
            r = self.executar()
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("sem permissão", r.stderr)
        finally:
            dados.chmod(0o700)


@unittest.skipUnless(RSCRIPT, "Rscript real indisponível")
class TestInstaladorRControlado(unittest.TestCase):
    def test_motor_real_com_fontes_instalacoes_e_rede_simuladas(self):
        # Executa o algoritmo R real, substituindo somente as operações de I/O
        # de pacotes. Nenhuma biblioteca real é instalada nem há acesso à rede.
        codigo = r'''
args_teste <- commandArgs(TRUE)
raiz <- args_teste[2]
e <- new.env(parent = globalenv())
e$commandArgs <- function(...) c("instalar", raiz, "--confirmado")
e$Sys.which <- function(x) setNames(rep("/bin/true", length(x)), x)
substituir <- function(x) {
  if (!is.call(x)) return(x)
  if (is.call(x[[1]]) && identical(x[[1]][[1]], as.name("::")) &&
      identical(x[[1]][[2]], as.name("utils"))) {
    nome <- as.character(x[[1]][[3]])
    if (nome %in% c("download.file", "untar", "install.packages", "packageDescription", "available.packages"))
      x[[1]] <- as.name(paste0("fake_", gsub("\\.", "_", nome)))
  }
  for (i in seq_along(x)[-1]) if (is.call(x[[i]])) x[[i]] <- substituir(x[[i]])
  x
}
expressoes <- parse(args_teste[1])
# Exclui somente o dispatcher e quit; carrega as funções originais.
for (x in head(expressoes, -2)) eval(substituir(x), e)
estado <- new.env(parent = emptyenv())
for (p in unique(c(names(e$politica), e$imports_microdatasus)))
  estado[[p]] <- list(Package = p, Version = "99.0")
estado$dplyr$Version <- "1.2.1"; estado$lubridate$Version <- "1.9.5"
rm(list = c("microdatasus", "jsonlite"), envir = estado)
e$descricao_instalada <- function(p) estado[[p]]
instalados <- character(); urls <- character(); falhar <- FALSE
e$fake_download_file <- function(url, destfile, ...) {
  urls <<- c(urls, url)
  if (falhar) stop("rede simulada indisponível")
  writeLines("fonte simulada", destfile); 0L
}
e$fake_available_packages <- function(...) matrix("2.0", 1, 1,
  dimnames = list("depTeste", "Version"))
e$fake_untar <- function(tarfile, list = FALSE, exdir = NULL, ...) {
  if (list) return("fonte/DESCRIPTION")
  p <- sub("_.*", "", basename(tarfile))
  versao <- if (p == "depTeste") "2.0" else e$versoes_instalacao[[p]]
  d <- c(Package = p, Version = versao, Depends = "R (>= 4.1.0)")
  if (p == "microdatasus") d <- c(d, Imports = "depTeste (>= 2.0), jsonlite")
  dir.create(file.path(exdir, "fonte"))
  write.dcf(as.data.frame(as.list(d)), file.path(exdir, "fonte", "DESCRIPTION"))
}
e$fake_install_packages <- function(pkgs, lib, repos, type, dependencies) {
  stopifnot(identical(lib, e$biblioteca), is.null(repos), identical(type, "source"), identical(dependencies, FALSE))
  d <- as.list(read.dcf(file.path(pkgs, "DESCRIPTION"))[1, ])
  instalados <<- c(instalados, d$Package); estado[[d$Package]] <- d
}
e$fake_packageDescription <- function(p, lib.loc) {
  stopifnot(identical(lib.loc, e$biblioteca)); estado[[p]]
}
# Confirmação é exigida antes de criar biblioteca.
e$args <- c("instalar", raiz)
stopifnot(inherits(try(e$instalar(), silent = TRUE), "try-error"), !dir.exists(e$biblioteca))
e$args <- c("instalar", raiz, "--confirmado")
e$instalar()
stopifnot(identical(instalados, c("depTeste", "jsonlite", "microdatasus")),
  any(grepl(e$commit_microdatasus, urls, fixed = TRUE)),
  identical(estado$microdatasus$Version, "3.0.0"),
  identical(estado$jsonlite$Version, "2.0.0"), length(e$planejar()) == 0L)
quantidade <- length(urls); e$instalar()
stopifnot(length(urls) == quantidade, length(instalados) == 3L)
rm("jsonlite", envir = estado); falhar <- TRUE
stopifnot(inherits(try(e$instalar(), silent = TRUE), "try-error"), is.null(estado$jsonlite))
cat("Instalação recursiva, versões, biblioteca, idempotência, consentimento e falha verificados com I/O simulado.\n")
'''
        with tempfile.TemporaryDirectory(prefix="import-mds-motor-r-") as temp:
            base = Path(temp)
            teste = base / "teste.R"
            teste.write_text(codigo, encoding="utf-8")
            r = subprocess.run([RSCRIPT, "--vanilla", str(teste),
                str(RAIZ / "R/configurar_ambiente.R"), str(base)],
                text=True, capture_output=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("I/O simulado", r.stdout)


@unittest.skipUnless(RSCRIPT, "Rscript real indisponível")
class TestFluxoRealSemGit(unittest.TestCase):
    def test_zip_equivalente_pacotes_reais_menu_e_conflito_antes_coleta(self):
        with tempfile.TemporaryDirectory(prefix="import-mds-fluxo-real-") as temp:
            base = Path(temp);projeto = base / "ZIP sem Git ' com espaços"
            copiar_projeto(projeto)
            self.assertFalse((projeto / ".git").exists())
            antes = snapshot(projeto)
            env = os.environ.copy();env["PYTHONDONTWRITEBYTECODE"] = "1"
            r = subprocess.run([BASH, str(projeto / "configurar.sh"), "--check"], cwd=base,
                input="n\n", text=True, capture_output=True, env=env, timeout=60)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            r = subprocess.run([BASH, str(projeto / "configurar.sh")], cwd=base,
                input="n\n", text=True, capture_output=True, env=env, timeout=60)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(snapshot(projeto), antes)
            # Defesa adicional: o R real recebe uma função global de coleta que
            # só falha. Não muda o pacote instalado; nunca acessa DATASUS.
            perfil = base / "perfil.R"
            perfil.write_text('fetch_datasus <- function(...) { stop("COLETA BLOQUEADA PELO TESTE") }\n', encoding="utf-8")
            env["R_PROFILE_USER"] = str(perfil)
            nome = "dados_SIM-DO_MA_2014_2014_cid-intervalo-E10-E14_idade_18mais"
            (projeto / "Dados" / nome).mkdir()
            antes_menu = snapshot(projeto)
            r = subprocess.run([BASH, str(projeto / "iniciar.sh")], cwd=base, env=env,
                input="1\n1\n2014\n2014\nMA\n3\n6\n18\n\nI10-I14\nE10-E14\n",
                text=True, capture_output=True, timeout=60)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("Tipo de dado:", r.stdout)
            self.assertIn("inexistente", r.stdout)
            self.assertIn("Diretório da extração já existe", r.stderr)
            self.assertNotIn("COLETA BLOQUEADA", r.stdout + r.stderr)
            self.assertNotIn("Dados coletados com sucesso", r.stdout)
            self.assertEqual(snapshot(projeto), antes_menu)


if __name__ == "__main__":
    unittest.main()
