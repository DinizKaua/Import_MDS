"""Entradas sintéticas e subprocesso simulado: nenhum R ou download é executado.

Executar da raiz: python3 -B -m unittest discover -s tests -p 'test_cli_*.py' -v
"""

import contextlib
import io
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import app


class TestFiltrosEtariosCLI(unittest.TestCase):
    def entradas(self, minimo="", maximo=""):
        # SIM, anual, anos, UF, sexo, raça, idades e CID, na ordem interativa.
        return ["1", "1", "2020", "2024", "ma", "1", "3", minimo, maximo, "i21"]

    def argumentos(self, *idades):
        return [
            "Rscript", str(Path(app.__file__).resolve().parent / "R" / "coletar_dados.R"),
            "--system", "SIM-DO",
            "--year_start", "2020", "--year_end", "2024",
            "--month_start", "1", "--month_end", "12",
            "--uf", "MA", "--sexo", "Masculino", "--cid", "I21", "--raca", "Parda",
            *idades,
        ]

    def executar(self, entradas, falha=None):
        saida = io.StringIO()
        with patch("builtins.input", side_effect=entradas), patch(
            "app.subprocess.run", side_effect=falha,
            return_value=subprocess.CompletedProcess([], 0),
        ) as executar_r, contextlib.redirect_stdout(saida):
            status = app.main()
        return status, executar_r, saida.getvalue()

    def test_limites_opcionais_e_argumentos_exatos(self):
        casos = [
            ("", "", []),
            ("18", "", ["--idade_min", "18"]),
            ("", "17", ["--idade_max", "17"]),
            ("18", "59", ["--idade_min", "18", "--idade_max", "59"]),
            ("18", "18", ["--idade_min", "18", "--idade_max", "18"]),
            ("0", "0", ["--idade_min", "0", "--idade_max", "0"]),
            ("0", "", ["--idade_min", "0"]),
            ("", "0", ["--idade_max", "0"]),
            ("100", "199", ["--idade_min", "100", "--idade_max", "199"]),
            ("0018", "0059", ["--idade_min", "18", "--idade_max", "59"]),
        ]
        for minimo, maximo, esperado in casos:
            with self.subTest(minimo=minimo, maximo=maximo):
                status, executar_r, saida = self.executar(self.entradas(minimo, maximo))
                self.assertEqual(status, 0)
                executar_r.assert_called_once_with(self.argumentos(*esperado), check=True)
                self.assertNotIn("--faixa", executar_r.call_args.args[0])
                self.assertIn("Dados coletados com sucesso!", saida)
                self.assertNotIn("18 a 39", saida)

    def test_entradas_invalidas_repetem_ambas_as_perguntas_sem_iniciar_r(self):
        invalidas = ["-1", "18.5", "18,5", "abc", "NaN", "Inf", "+18", "1e2",
                     " 18", "18 ", " ", "18\n", "²", "１８"]
        for indice, pergunta in [(7, "mínima"), (8, "máxima")]:
            for invalida in invalidas:
                with self.subTest(pergunta=pergunta, entrada=invalida):
                    entradas = self.entradas("18", "59")
                    entradas.insert(indice, invalida)
                    saida = io.StringIO()
                    with patch("app.subprocess.run") as executar_r:
                        def responder(_):
                            # Nem a entrada inválida nem sua correção disparam o R.
                            executar_r.assert_not_called()
                            return entradas.pop(0)

                        with patch("builtins.input", side_effect=responder) as ler, contextlib.redirect_stdout(saida):
                            self.assertEqual(app.main(), 0)
                        executar_r.assert_called_once_with(
                            self.argumentos("--idade_min", "18", "--idade_max", "59"), check=True,
                        )
                        self.assertEqual(sum(f"Idade {pergunta}" in c.args[0] for c in ler.call_args_list), 2)
                    self.assertIn("inteiro não negativo", saida.getvalue())
                    self.assertEqual(entradas, [])

    def test_minimo_maior_que_maximo_repete_maximo(self):
        entradas = self.entradas("60", "59")
        entradas.insert(9, "60")
        status, executar_r, saida = self.executar(entradas)
        self.assertEqual(status, 0)
        executar_r.assert_called_once_with(self.argumentos("--idade_min", "60", "--idade_max", "60"), check=True)
        self.assertIn("máxima não pode ser menor", saida)

    def test_sem_correcao_de_entrada_invalida_nunca_inicia_r(self):
        for idades in [("-1",), ("18.5",), ("abc",), ("60", "59")]:
            with self.subTest(idades=idades), patch("builtins.input", side_effect=[
                *self.entradas()[:7], *idades,
            ]), patch("app.subprocess.run") as executar_r, contextlib.redirect_stdout(io.StringIO()):
                # Interrompe as respostas na repetição, sem fornecer uma correção.
                with self.assertRaises(StopIteration):
                    app.main()
                executar_r.assert_not_called()

    def test_limite_tecnico_igual_ao_r(self):
        status, executar_r, _ = self.executar(self.entradas("9007199254740991", ""))
        self.assertEqual(status, 0)
        executar_r.assert_called_once_with(self.argumentos("--idade_min", "9007199254740991"), check=True)
        for invalida in ["9007199254740992", "9" * 5000]:
            with self.subTest(entrada=invalida[:20]):
                entradas = self.entradas("18", "")
                entradas.insert(7, invalida)
                status, executar_r, saida = self.executar(entradas)
                self.assertEqual(status, 0)
                self.assertIn("limite técnico", saida)
                executar_r.assert_called_once_with(self.argumentos("--idade_min", "18"), check=True)

    def test_demais_parametros_mensais_e_nacionais_preservados(self):
        status, executar_r, _ = self.executar([
            "2", "2", "2021", "2022", "3", "8", "all", "2", "5", "", "17", "c50",
        ])
        self.assertEqual(status, 0)
        executar_r.assert_called_once_with([
            "Rscript", str(Path(app.__file__).resolve().parent / "R" / "coletar_dados.R"), "--system", "SIH-RD",
            "--year_start", "2021", "--year_end", "2022",
            "--month_start", "3", "--month_end", "8", "--uf", "ALL",
            "--sexo", "Feminino", "--cid", "C50", "--raca", "Indigena", "--idade_max", "17",
        ], check=True)

    def test_demais_filtros_sem_restricao_preservados(self):
        entradas = self.entradas()
        entradas[5], entradas[6], entradas[-1] = "3", "6", "ALL"
        status, executar_r, _ = self.executar(entradas)
        self.assertEqual(status, 0)
        esperado = self.argumentos()
        for chave in ["--sexo", "--raca", "--cid"]:
            esperado[esperado.index(chave) + 1] = "ALL"
        executar_r.assert_called_once_with(esperado, check=True)

    def test_falhas_do_r_nao_anunciam_sucesso(self):
        for motivo, codigo in [("validação", 1), ("destino existente", 2),
                               ("coleta", 3), ("exportação", 4), ("sinal", -9)]:
            with self.subTest(motivo=motivo):
                status, executar_r, saida = self.executar(
                    self.entradas(), subprocess.CalledProcessError(codigo, ["Rscript"]),
                )
                self.assertEqual(status, codigo if codigo > 0 else 1)
                executar_r.assert_called_once_with(self.argumentos(), check=True)
                self.assertIn("Erro ao executar o script R", saida)
                self.assertNotIn("Dados coletados com sucesso!", saida)

    def test_rscript_ausente(self):
        status, executar_r, saida = self.executar(self.entradas(), FileNotFoundError("Rscript"))
        self.assertEqual(status, 127)
        executar_r.assert_called_once_with(self.argumentos(), check=True)
        self.assertIn("Executável Rscript não encontrado", saida)
        self.assertNotIn("Dados coletados com sucesso!", saida)

    def test_outra_falha_ao_iniciar_rscript(self):
        status, _, saida = self.executar(self.entradas(), PermissionError("sem permissão"))
        self.assertEqual(status, 1)
        self.assertIn("Não foi possível iniciar o Rscript", saida)
        self.assertNotIn("Dados coletados com sucesso!", saida)

    def test_ponto_de_entrada_propaga_codigo_de_saida(self):
        for falha, esperado in [(None, 0), (subprocess.CalledProcessError(7, ["Rscript"]), 7),
                                (FileNotFoundError("Rscript"), 127)]:
            with self.subTest(status=esperado), patch("builtins.input", side_effect=self.entradas()), patch(
                "subprocess.run", side_effect=falha, return_value=subprocess.CompletedProcess([], 0),
            ) as executar_r, contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as encerramento:
                    runpy.run_path(str(Path(app.__file__)), run_name="__main__")
                self.assertEqual(encerramento.exception.code, esperado)
                executar_r.assert_called_once_with(self.argumentos(), check=True)

    def test_execucao_fora_da_raiz_preserva_caminho_do_script(self):
        anterior = Path.cwd()
        try:
            with tempfile.TemporaryDirectory(prefix="import mds cli ") as pasta:
                os.chdir(pasta)
                status, executar_r, _ = self.executar(self.entradas("18", "59"))
                self.assertEqual(status, 0)
                executar_r.assert_called_once_with(
                    self.argumentos("--idade_min", "18", "--idade_max", "59"), check=True,
                )
                self.assertTrue(Path(executar_r.call_args.args[0][1]).is_absolute())
                self.assertTrue(Path(executar_r.call_args.args[0][1]).is_file())
        finally:
            os.chdir(anterior)


if __name__ == "__main__":
    unittest.main()
