#!/usr/bin/env python3
"""Genera Credentials/lingo-identity.json a partir de LingoCredentials.java de Juggluco.

Uso:
    python3 -I tools/make_lingo_identity.py <ruta a LingoCredentials.java> [salida.json]

- Lee los tres arrays (APP_PRIVATE 32 B, APP_CERTIFICATE 162 B, PATCH_SIGNING_PUBLIC 65 B).
- Comprueba tamaños y cabeceras (certificado `03 01`, clave pública `04`).
- Si `cryptography` está disponible, deriva la clave pública P-256 del escalar privado y
  comprueba que coincide con los bytes 33..98 del certificado, y que la clave de firma está
  en la curva.
- Escribe el JSON con el formato de Credentials/README.md (formato 1, P-256) y permisos 0600.
- NUNCA imprime los valores: solo tamaños y resultados de verificación.

El archivo de salida está en .gitignore. Uso personal autorizado por Juampa (2026-10-27).
"""
import json
import os
import re
import sys
from pathlib import Path

NAMES = {"APP_PRIVATE": 32, "APP_CERTIFICATE": 162, "PATCH_SIGNING_PUBLIC": 65}


def parse_arrays(src: str) -> dict[str, bytes]:
    out = {}
    for name, size in NAMES.items():
        m = re.search(name + r"\s*=\s*(?:new byte\[\]\s*)?\{(.*?)\}", src, re.S)
        if not m:
            raise SystemExit(f"{name}: no encontrado")
        vals = re.findall(r"0x([0-9a-fA-F]{1,2})", m.group(1))
        data = bytes(int(v, 16) for v in vals)
        if len(data) != size:
            raise SystemExit(f"{name}: {len(data)} bytes, se esperaban {size}")
        out[name] = data
    return out


def verify(arrays: dict[str, bytes]) -> list[str]:
    notes = []
    cert = arrays["APP_CERTIFICATE"]
    if cert[:2] != b"\x03\x01":
        raise SystemExit("certificado: cabecera distinta de 03 01")
    if cert[33] != 0x04:
        raise SystemExit("certificado: byte 33 no es 0x04 (punto sin comprimir)")
    if arrays["PATCH_SIGNING_PUBLIC"][0] != 0x04:
        raise SystemExit("clave de firma: no empieza por 0x04")
    try:
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        notes.append("cryptography no disponible: no se verificó la correspondencia clave/certificado")
        return notes
    scalar = int.from_bytes(arrays["APP_PRIVATE"], "big")
    priv = ec.derive_private_key(scalar, ec.SECP256R1())
    pub = priv.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    if pub != cert[33:98]:
        raise SystemExit("la clave pública derivada NO coincide con el certificado (bytes 33..98)")
    notes.append("clave pública derivada == certificado[33..98]: OK")
    ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), arrays["PATCH_SIGNING_PUBLIC"])
    notes.append("clave de firma del parche está en la curva P-256: OK")
    return notes


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "Credentials" / "lingo-identity.json"
    arrays = parse_arrays(src_path.read_text(encoding="utf-8"))
    notes = verify(arrays)
    identity = {
        "format": 1,
        "curve": "P-256",
        "identities": [
            {
                "label": "lingo-v3",
                "productTypes": [9],
                "securityVersions": [3],
                "privateKeyHex": arrays["APP_PRIVATE"].hex(),
                "certificateHex": arrays["APP_CERTIFICATE"].hex(),
                "patchSigningPublicKeyHex": arrays["PATCH_SIGNING_PUBLIC"].hex(),
            }
        ],
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(identity, f, indent=2)
        f.write("\n")
    os.chmod(out_path, 0o600)
    print(f"escrito: {out_path} ({out_path.stat().st_size} bytes, permisos 0600)")
    for name, size in NAMES.items():
        print(f"  {name}: {size} B")
    for n in notes:
        print(f"  {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
