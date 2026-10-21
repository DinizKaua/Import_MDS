"""CID sintético/referência local, sem iniciar R ou acessar servidores."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import app


class TestIntervaloCID(unittest.TestCase):
    def test_prefixos_literais_sem_carregar_referencia(self):
        for cid in ["I2", "I21", "I210", "I21.0", "ALL", "", " I21 ", "DRC"]:
            with self.subTest(cid=cid), patch("app.json.load", side_effect=AssertionError("não deve carregar")):
                self.assertEqual(app.interpretar_intervalo_cid(cid), cid)

    def test_intervalos_e_lacunas_reais(self):
        for cid in ["I10-I15", "i10-i15", " I10 - I15 ", "I10\t-\tI15"]:
            self.assertEqual(app.interpretar_intervalo_cid(cid), "I10-I15")
        self.assertEqual(app.interpretar_intervalo_cid("I10-I10"), "I10-I10")
        self.assertEqual(app.interpretar_intervalo_cid("A00-A04"), "A00-A04")
        with self.assertRaisesRegex(ValueError, "inexistente"):
            app.interpretar_intervalo_cid("I10-I14")

    def test_entradas_invalidas(self):
        for cid in ["I15-I10", "I10-J15", "I10--I15", "I 10-I15", "I1-I15", "I10-I150", "I10-", "-I15", "I10-I15\n"]:
            with self.subTest(cid=cid), self.assertRaises(ValueError):
                app.interpretar_intervalo_cid(cid)

    def test_referencia_controlada_com_lacunas(self):
        r = {"versao_indice": "1.0.0", "categorias": ["A00", "A02", "A04"],
             "referencia": {"quantidade_categorias": 3}}
        self.assertEqual(app.interpretar_intervalo_cid("A00-A04", r), "A00-A04")
        with self.assertRaises(ValueError):
            app.interpretar_intervalo_cid("A00-A01", r)
        r["referencia"]["quantidade_categorias"] = 4
        with self.assertRaises(RuntimeError):
            app.interpretar_intervalo_cid("A00-A04", r)

    def test_pergunta_repete_sem_iniciar_subprocesso(self):
        respostas = ["I15-I10", "I10-I14", "i10 - i15"]
        with patch("app.subprocess.run") as run, contextlib.redirect_stdout(io.StringIO()) as saida:
            def responder(_):
                run.assert_not_called()
                return respostas.pop(0)
            with patch("builtins.input", side_effect=responder):
                self.assertEqual(app.escolher_doenca(), "I10-I15")
            run.assert_not_called()
            self.assertIn("invertidos", saida.getvalue())
            self.assertIn("inexistente", saida.getvalue())
        for entrada, esperado in [("", "ALL"), (" i21 ", " I21 "), ("i210", "I210")]:
            with patch("builtins.input", return_value=entrada), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(app.escolher_doenca(), esperado)

    def test_argumentos_e_erro_de_referencia(self):
        entradas = ["1", "1", "2014", "2014", "MA", "3", "6", "18", "", "I10-I14", "I10-I15"]
        with patch("builtins.input", side_effect=entradas), patch("app.subprocess.run") as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(app.main(), 0)
            args = run.call_args.args[0]
            self.assertEqual(args[args.index("--cid") + 1], "I10-I15")
            self.assertEqual(args[args.index("--idade_min") + 1], "18")
            run.assert_called_once()
        with patch("app.escolher_doenca", side_effect=RuntimeError("referência ausente")), patch(
            "builtins.input", side_effect=entradas[:9]
        ), patch("app.subprocess.run") as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(app.main(), 1)
            run.assert_not_called()

    def test_referencia_reproduzivel_offline(self):
        raiz = Path(app.__file__).resolve().parent
        spec = importlib.util.spec_from_file_location("gerador_cid", raiz / "scripts/gerar_referencia_cid10.py")
        gerador = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gerador)
        referencia = json.loads((raiz / "referencias/cid10/oms_2019_codigos.json").read_text(encoding="utf-8"))
        reproduzida = gerador.gerar(raiz / "referencias/cid10/icd102019en.xml.zip", referencia["referencia"]["obtido_em_utc"])
        self.assertEqual(reproduzida, referencia)
        self.assertEqual(len(referencia["categorias"]), 2090)
        self.assertNotIn("I14", referencia["categorias"])
        with tempfile.TemporaryDirectory() as temp:
            invalido = Path(temp) / "alterado.zip"
            invalido.write_bytes(b"referencia incorreta")
            with self.assertRaises(ValueError):
                gerador.gerar(invalido, "2026-10-21T00:51:39Z")


if __name__ == "__main__":
    unittest.main()
