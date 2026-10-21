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
    return {
        "versao_indice": "1.0.0",
        "referencia": {
            "origem": "OMS", "versao": titulo.attrib["version"],
            "identificador": identificador.attrib["uid"], "data_titulo": titulo.attrib["date"],
            "url": URL, "obtido_em_utc": obtido_em,
            "sha256_zip": SHA256_ZIP, "sha256_xml": hashlib.sha256(xml).hexdigest(),
            "quantidade_categorias": len(categorias), "quantidade_subcategorias": len(subcategorias),
            "escopo": "Classes category explícitas de três caracteres e suas subcategorias explícitas; sem expansão de modificadores."
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
