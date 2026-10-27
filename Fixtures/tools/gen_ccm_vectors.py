#!/usr/bin/env python3
"""Genera Fixtures/ccm_vectors.json con la libreria independiente `cryptography`.

Uso: python3 -I gen_ccm_vectors.py [--seed N] [--out RUTA]
Perfiles: data_plane (nonce 13 B, L=2, M=4) y challenge (nonce 7 B, L=8, M=4), sin AAD.
"""
import argparse, json, os, random, sys
from cryptography.hazmat.primitives.ciphers.aead import AESCCM

PROFILES = {
    "data_plane": {"nonce_len": 13, "L": 2, "M": 4, "aad": False},
    "challenge": {"nonce_len": 7, "L": 8, "M": 4, "aad": False},
}
LENGTHS = [1, 15, 29, 35, 51, 57, 2, 16, 17, 31, 32, 33, 48, 63, 64, 65, 80, 99, 110, 120]
MUTATIONS = ["tag_flip", "tag_flip", "nonce_flip", "nonce_flip", "ciphertext_flip",
             "ciphertext_flip", "truncated", "truncated", "wrong_key", "wrong_key"]

def rb(rng, n):
    return bytes(rng.getrandbits(8) for _ in range(n))

def flip(b, idx, mask):
    x = bytearray(b); x[idx] ^= mask; return bytes(x)

def build(seed):
    rng = random.Random(seed)
    out = {"generator": "gen_ccm_vectors.py", "seed": seed,
           "library": "python-cryptography AESCCM(tag_length=4)",
           "profiles": {}, "vectors": {}, "reference_vectors": []}
    for name, p in PROFILES.items():
        out["profiles"][name] = {"nonce_length": p["nonce_len"], "L": p["L"], "M": p["M"], "aad": ""}
        pos, neg = [], []
        for i, n in enumerate(LENGTHS):
            key, nonce, pt = rb(rng, 16), rb(rng, p["nonce_len"]), rb(rng, n)
            enc = AESCCM(key, tag_length=4).encrypt(nonce, pt, None)
            pos.append({"id": f"{name}-pos-{i+1:02d}", "key_hex": key.hex(), "nonce_hex": nonce.hex(),
                        "plaintext_hex": pt.hex(), "ciphertext_hex": enc[:-4].hex(),
                        "tag_hex": enc[-4:].hex(), "expect": "ok"})
        for i, mut in enumerate(MUTATIONS):
            base = dict(pos[[1, 2, 3, 4, 5, 6, 8, 9, 10, 11][i]])  # longitudes >= 15
            key = bytes.fromhex(base["key_hex"]); nonce = bytes.fromhex(base["nonce_hex"])
            ct = bytes.fromhex(base["ciphertext_hex"]); tag = bytes.fromhex(base["tag_hex"])
            if mut == "tag_flip":
                tag = flip(tag, rng.randrange(4), rng.randrange(1, 256))
            elif mut == "nonce_flip":
                nonce = flip(nonce, rng.randrange(len(nonce)), rng.randrange(1, 256))
            elif mut == "ciphertext_flip":
                ct = flip(ct, rng.randrange(len(ct)), rng.randrange(1, 256))
            elif mut == "truncated":
                ct = ct[:-rng.randrange(1, 4)]
            elif mut == "wrong_key":
                key = flip(key, rng.randrange(16), rng.randrange(1, 256))
            # comprobar con la libreria independiente que de verdad falla
            try:
                AESCCM(key, tag_length=4).decrypt(nonce, ct + tag, None)
                sys.exit(f"mutacion {mut} no provoco fallo")
            except Exception as e:
                if type(e).__name__ != "InvalidTag":
                    raise
            neg.append({"id": f"{name}-neg-{i+1:02d}", "key_hex": key.hex(), "nonce_hex": nonce.hex(),
                        "plaintext_hex": base["plaintext_hex"], "ciphertext_hex": ct.hex(),
                        "tag_hex": tag.hex(), "expect": "auth_failure", "mutation": mut})
        out["vectors"][name] = pos + neg
    # Referencia publica: RFC 3610 solo usa M=8 (vectores 1-12) y M=10 (13-24): ninguno con M=4.
    # NIST SP 800-38C Ejemplo 1 si es M=4 (Tlen=32), nonce 7 B, con AAD de 8 B.
    ref = {"id": "nist-sp800-38c-ex1", "source": "NIST SP 800-38C Appendix C, Example 1",
           "key_hex": bytes(range(0x40, 0x50)).hex(), "nonce_hex": "10111213141516",
           "aad_hex": "0001020304050607", "plaintext_hex": "20212223",
           "ciphertext_hex": "7162015b", "tag_hex": "4dac255d", "expect": "ok"}
    got = AESCCM(bytes.fromhex(ref["key_hex"]), tag_length=4).encrypt(
        bytes.fromhex(ref["nonce_hex"]), bytes.fromhex(ref["plaintext_hex"]), bytes.fromhex(ref["aad_hex"]))
    assert got.hex() == ref["ciphertext_hex"] + ref["tag_hex"], got.hex()
    out["reference_vectors"].append(ref)
    out["notes"] = "RFC 3610 no aporta vectores con M=4 (sus paquetes usan M=8 y M=10); se incluye NIST SP 800-38C Ej.1 (M=4, con AAD)."
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=20260101)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ccm_vectors.json"))
    a = ap.parse_args()
    for n in (7, 13):
        AESCCM(bytes(16), tag_length=4).encrypt(bytes(n), b"x", None)
    data = build(a.seed)
    with open(a.out, "w") as f:
        json.dump(data, f, indent=1); f.write("\n")
    for name, vs in data["vectors"].items():
        pos = [v for v in vs if v["expect"] == "ok"]
        print(name, "positivos", len(pos), "negativos", len(vs) - len(pos),
              "longitudes", sorted(len(v["plaintext_hex"]) // 2 for v in pos))
    print("referencia:", [r["id"] for r in data["reference_vectors"]], "->", os.path.normpath(a.out))

main()
