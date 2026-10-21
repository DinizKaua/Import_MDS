"""Expansão direcionada de diabetes: XML local e fixtures em memória, sem rede."""

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile


RAIZ = Path(__file__).resolve().parents[1]
SCRIPT = RAIZ / "scripts/gerar_referencia_cid10.py"
ZIP = RAIZ / "referencias/cid10/icd102019en.xml.zip"
INDICE = RAIZ / "referencias/cid10/oms_2019_codigos.json"
spec = importlib.util.spec_from_file_location("gerador_diabetes", SCRIPT)
gerador = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gerador)


def fixture():
    raiz = ET.Element("ClaML", version="2.0.0")
    mod = ET.SubElement(raiz, "Modifier", code="S04E10_4")
    for i in range(10):
        ET.SubElement(mod, "SubClass", code=f".{i}")
        classe = ET.SubElement(raiz, "ModifierClass", code=f".{i}", modifier="S04E10_4")
        ET.SubElement(classe, "SuperClass", code="S04E10_4")
    for codigo in ("E10", "E11", "E12", "E13", "E14"):
        classe = ET.SubElement(raiz, "Class", code=codigo, kind="category")
        ET.SubElement(classe, "SuperClass", code="E10-E14")
        ET.SubElement(classe, "ModifiedBy", code="S04E10_4")
    return raiz


class TestGeradorDiabetes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bytes_zip = ZIP.read_bytes()
        with zipfile.ZipFile(ZIP) as pacote:
            cls.xml = pacote.read("icd102019en.xml")
        cls.raiz = ET.fromstring(cls.xml)
        cls.indice = json.loads(INDICE.read_text(encoding="utf-8"))
        cls.esperados = {f"E{c}.{s}" for c in range(10, 15) for s in range(10)}

    def test_cinquenta_codigos_e_vinculos_da_fonte(self):
        derivados = gerador.expandir_diabetes(self.raiz)
        self.assertEqual(set(derivados), self.esperados)
        self.assertEqual(len(derivados), 50)
        self.assertEqual(len(set(derivados)), 50)
        self.assertEqual(gerador.expandir_diabetes(fixture()), sorted(self.esperados))

    def test_preserva_explicitos_e_expande_somente_alvo(self):
        explicitos = {c.attrib["code"] for c in self.raiz.findall("Class") if c.get("kind") == "category"}
        categorias = {c for c in explicitos if len(c) == 3}
        subcategorias = explicitos - categorias
        self.assertEqual(len(categorias), 2090)
        self.assertEqual(len(subcategorias), 9153)
        self.assertEqual(set(self.indice["categorias"]), categorias)
        self.assertEqual(set(self.indice["subcategorias"]) - subcategorias, self.esperados)
        self.assertEqual(subcategorias - set(self.indice["subcategorias"]), set())
        self.assertEqual(len(self.indice["subcategorias"]), 9203)
        self.assertEqual(len(set(self.indice["subcategorias"])), 9203)
        # F10 também usa modificador, mas continua sem expansão nesta correção.
        self.assertNotIn("F10.0", self.indice["subcategorias"])
        self.assertNotIn("I14", self.indice["categorias"])

    def test_metadados_compativeis_e_procedencia_preservada(self):
        r = self.indice["referencia"]
        self.assertEqual(self.indice["versao_indice"], "1.0.0")
        self.assertEqual(r["versao"], "2019-covid-expanded")
        self.assertEqual(r["identificador"], "icd10_20210322")
        self.assertEqual(r["sha256_zip"], gerador.SHA256_ZIP)
        self.assertEqual(r["sha256_xml"], hashlib.sha256(self.xml).hexdigest())
        self.assertEqual(r["geracao"]["versao"], "1.1.0")
        self.assertEqual(r["geracao"]["codigos_derivados"], sorted(self.esperados))
        self.assertEqual(r["geracao"]["quantidade_subcategorias_explicitas"], 9153)
        self.assertEqual(r["geracao"]["quantidade_subcategorias_adicionadas"], 50)
        self.assertEqual(r["geracao"]["outros_modificadores"], "nao_expandidos")

    def test_geracao_deterministica_bytes_e_zip_intacto(self):
        with tempfile.TemporaryDirectory() as temp:
            caminhos = [Path(temp) / nome for nome in ("primeiro.json", "segundo.json")]
            for caminho in caminhos:
                resultado = subprocess.run([sys.executable, "-B", str(SCRIPT), str(ZIP), str(caminho),
                    "--obtido-em", self.indice["referencia"]["obtido_em_utc"]], capture_output=True, text=True)
                self.assertEqual(resultado.returncode, 0, resultado.stderr)
            self.assertEqual(caminhos[0].read_bytes(), caminhos[1].read_bytes())
            self.assertEqual(caminhos[0].read_bytes(), INDICE.read_bytes())
            resultado = subprocess.run([sys.executable, "-B", str(SCRIPT), str(ZIP), str(caminhos[0]),
                "--obtido-em", self.indice["referencia"]["obtido_em_utc"]], capture_output=True)
            self.assertNotEqual(resultado.returncode, 0)
            self.assertEqual(caminhos[0].read_bytes(), INDICE.read_bytes())
        self.assertEqual(ZIP.read_bytes(), self.bytes_zip)

    def test_sufixos_lidos_sem_depender_da_ordem(self):
        r = fixture()
        mod = r.find("Modifier")
        mod[:] = list(reversed(list(mod)))
        r[:] = list(reversed(list(r)))
        for classe in r.findall("Class"):
            classe.find("ModifiedBy").set("all", "true")
        antes = ET.tostring(r)
        self.assertEqual(gerador.expandir_diabetes(r), sorted(self.esperados))
        self.assertEqual(ET.tostring(r), antes)

    def test_nao_expande_outro_modificador(self):
        r = fixture()
        outro = ET.SubElement(r, "Modifier", code="OUTRO")
        ET.SubElement(outro, "SubClass", code=".7")
        classe = ET.SubElement(r, "Class", code="E15", kind="category")
        ET.SubElement(classe, "ModifiedBy", code="OUTRO")
        self.assertEqual(gerador.expandir_diabetes(r), sorted(self.esperados))

    def test_rejeita_definicao_ausente_duplicada_ou_sufixos_alterados(self):
        for caso in range(6):
            r = fixture(); m = r.find("Modifier")
            if caso == 0: r.remove(m)
            elif caso == 1: r.append(copy.deepcopy(m))
            elif caso == 2: m.remove(m[0])
            elif caso == 3: m[0].set("code", ".00")
            elif caso == 4: m.append(copy.deepcopy(m[0]))
            else: ET.SubElement(m, "Meta", name="restricao_desconhecida", value="x")
            with self.subTest(caso=caso), self.assertRaisesRegex(ValueError, "Estrutura inesperada"):
                gerador.expandir_diabetes(r)

    def test_rejeita_vinculos_ou_categorias_inesperados(self):
        for caso in range(6):
            r = fixture(); c = r.find("Class")
            if caso == 0: c.remove(c.find("ModifiedBy"))
            elif caso == 1: c.set("code", "E15")
            elif caso == 2: r.append(copy.deepcopy(c))
            elif caso == 3: c.set("kind", "block")
            elif caso == 4: ET.SubElement(c, "ModifiedBy", code="OUTRO")
            else: c.find("SuperClass").set("code", "OUTRO-BLOCO")
            with self.subTest(caso=caso), self.assertRaises(ValueError):
                gerador.expandir_diabetes(r)

    def test_rejeita_restricoes_exclusoes_e_quinto_caractere(self):
        for caso in range(7):
            r = fixture(); c = r.find("Class"); m = c.find("ModifiedBy")
            if caso == 0: m.set("all", "false"); ET.SubElement(m, "ValidModifierClass", code=".0")
            elif caso == 1: ET.SubElement(m, "ValidModifierClass", code=".0")
            elif caso == 2: ET.SubElement(c, "ExcludeModifier", code="S04E10_4")
            elif caso == 3: m.set("position", "5")
            elif caso == 4: m.set("variants", "local")
            elif caso == 5: ET.SubElement(c, "SubClass", code="E10.0")
            else: m.set("all", "false")
            with self.subTest(caso=caso), self.assertRaises(ValueError):
                gerador.expandir_diabetes(r)

    def test_rejeita_modifierclass_incompleta_ou_com_restricoes(self):
        for caso in range(5):
            r = fixture(); c = r.find("ModifierClass")
            if caso == 0: r.remove(c)
            elif caso == 1: c.find("SuperClass").set("code", "OUTRO")
            elif caso == 2: ET.SubElement(c, "Meta", name="excludeOnPrecedingModifier", value="OUTRO .0")
            elif caso == 3: c.set("variants", "local")
            else: r.append(copy.deepcopy(c))
            with self.subTest(caso=caso), self.assertRaises(ValueError):
                gerador.expandir_diabetes(r)

    def test_sobreposicao_explicita_derivada_nao_duplica(self):
        r = copy.deepcopy(self.raiz)
        ET.SubElement(r, "Class", code="E10.0", kind="category")
        with patch.object(gerador.ET, "fromstring", return_value=r):
            indice = gerador.gerar(ZIP, self.indice["referencia"]["obtido_em_utc"])
        self.assertEqual(indice["subcategorias"].count("E10.0"), 1)
        self.assertEqual(len(indice["subcategorias"]), 9203)
        self.assertEqual(indice["referencia"]["geracao"]["quantidade_subcategorias_adicionadas"], 49)


if __name__ == "__main__":
    unittest.main()
