"""Gera o índice local a partir do ZIP oficial já disponível, sem acesso à rede.

Uso e procedência: docs/cid10.md. Apenas biblioteca padrão Python.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

SHA256_ZIP = "344c571aa9aed3b9ad1c80261b7828c45cfb5fc0b1a5da64aecef354dff5b3d9"
URL = "https://icdcdn.who.int/icd10/claml/icd102019en.xml.zip"
VERSAO_GERADOR = "1.1.0"


def expandir_diabetes(raiz):
    """Expande somente a estrutura S04E10_4 aprovada; não interpreta ClaML geral.

    Uma mudança nos vínculos, sufixos ou restrições exige nova revisão. Rubricas
    e metadados descritivos das categorias não participam da construção de códigos.
    """
    modificador = "S04E10_4"
    esperadas = {"E10", "E11", "E12", "E13", "E14"}

    def exigir(condicao):
        if not condicao:
            raise ValueError("Estrutura inesperada de S04E10_4; expansão requer revisão.")

    def codigo_simples(no):
        exigir(set(no.attrib) == {"code"} and not len(no))
        return no.attrib["code"]

    exigir(raiz.tag == "ClaML" and raiz.get("version") == "2.0.0")
    definicoes = [n for n in raiz.findall("Modifier") if n.get("code") == modificador]
    exigir(len(definicoes) == 1)
    definicao = definicoes[0]
    exigir(definicao.attrib == {"code": modificador})
    exigir(all(n.tag in {"SubClass", "Rubric"} for n in definicao))
    sufixos = [codigo_simples(n) for n in definicao.findall("SubClass")]
    exigir(len(sufixos) == 10 and set(sufixos) == {f".{i}" for i in range(10)})

    classes = [n for n in raiz.findall("ModifierClass") if n.get("modifier") == modificador]
    exigir(len(classes) == 10 and {n.get("code") for n in classes} == set(sufixos))
    for classe in classes:
        exigir(set(classe.attrib) <= {"code", "modifier", "usage"})
        exigir(classe.get("usage") in {None, "dagger"})
        exigir(all(n.tag in {"SuperClass", "Rubric"} for n in classe))
        superiores = classe.findall("SuperClass")
        exigir(len(superiores) == 1 and codigo_simples(superiores[0]) == modificador)

    # Não ignorar vínculos extras, restrições ou exclusões aplicadas ao alvo.
    referencias = [n for n in raiz.iter("ModifiedBy") if n.get("code") == modificador]
    exigir(len(referencias) == 5)
    exigir(not any(n.get("code") == modificador for n in raiz.iter("ExcludeModifier")))
    categorias = []
    for categoria in raiz.findall("Class"):
        vinculos = [n for n in categoria.findall("ModifiedBy") if n.get("code") == modificador]
        if not vinculos:
            continue
        exigir(categoria.attrib == {"code": categoria.get("code"), "kind": "category"})
        exigir(categoria.get("code") in esperadas)
        exigir(all(n.tag in {"Meta", "SuperClass", "ModifiedBy", "Rubric"} for n in categoria))
        superiores = categoria.findall("SuperClass")
        exigir(len(superiores) == 1 and codigo_simples(superiores[0]) == "E10-E14")
        exigir(len(categoria.findall("ModifiedBy")) == 1)
        vinculo = vinculos[0]
        # all omitido equivale a true no ClaML. Qualquer lista restritiva,
        # posição, variante ou metadado técnico diferente exige revisão.
        exigir(set(vinculo.attrib) <= {"code", "all"})
        exigir(vinculo.get("all", "true") == "true" and not len(vinculo))
        categorias.append(categoria.get("code"))
    exigir(len(categorias) == 5 and set(categorias) == esperadas)
    return sorted(c + s for c in categorias for s in sufixos)


def gerar(arquivo_zip, obtido_em):
    bruto = Path(arquivo_zip).read_bytes()
    if hashlib.sha256(bruto).hexdigest() != SHA256_ZIP:
        raise ValueError("ZIP divergente da referência oficial fixada.")
    with zipfile.ZipFile(arquivo_zip) as pacote:
        xml = pacote.read("icd102019en.xml")
    raiz = ET.fromstring(xml)
    titulo, identificador = raiz.find("Title"), raiz.find("Identifier")
    codigos = [c.attrib["code"] for c in raiz.findall("Class") if c.attrib.get("kind") == "category"]
    if len(codigos) != len(set(codigos)):
        raise ValueError("Códigos duplicados na referência.")
    categorias = sorted(c for c in codigos if re.fullmatch(r"[A-Z][0-9]{2}", c))
    subcategorias = sorted(c for c in codigos if re.fullmatch(r"[A-Z][0-9]{2}\.[0-9]", c))
    if len(categorias) + len(subcategorias) != len(codigos):
        raise ValueError("Formato de classe não reconhecido; não gerar índice parcial.")
    if any(c[:3] not in categorias for c in subcategorias):
        raise ValueError("Subcategoria sem categoria correspondente.")
    derivadas = expandir_diabetes(raiz)
    explicitas = set(subcategorias)
    subcategorias = sorted(explicitas | set(derivadas))
    return {
        "versao_indice": "1.0.0",
        "referencia": {
            "origem": "OMS", "versao": titulo.attrib["version"],
            "identificador": identificador.attrib["uid"], "data_titulo": titulo.attrib["date"],
            "url": URL, "obtido_em_utc": obtido_em,
            "sha256_zip": SHA256_ZIP, "sha256_xml": hashlib.sha256(xml).hexdigest(),
            "quantidade_categorias": len(categorias), "quantidade_subcategorias": len(subcategorias),
            "escopo": "Classes category explícitas e expansão direcionada de S04E10_4; demais modificadores não expandidos.",
            "geracao": {
                "versao": VERSAO_GERADOR,
                "modificador_expandido": "S04E10_4",
                "categorias": sorted({c[:3] for c in derivadas}),
                "codigos_derivados": derivadas,
                "quantidade_subcategorias_explicitas": len(explicitas),
                "quantidade_subcategorias_derivadas": len(derivadas),
                "quantidade_subcategorias_adicionadas": len(set(derivadas) - explicitas),
                "outros_modificadores": "nao_expandidos",
            },
        },
        "categorias": categorias, "subcategorias": subcategorias,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("arquivo_zip", type=Path)
    parser.add_argument("destino", type=Path)
    parser.add_argument("--obtido-em", required=True)
    args = parser.parse_args()
    conteudo = gerar(args.arquivo_zip, args.obtido_em)
    # Nunca substituir uma referência existente durante reprodução.
    with args.destino.open("x", encoding="utf-8", newline="\n") as arquivo:
        json.dump(conteudo, arquivo, ensure_ascii=False, indent=2)
        arquivo.write("\n")
