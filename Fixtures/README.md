# Fixtures

## ccm_vectors.json (T-04)
Vectores AES-128-CCM con tag de 4 B y sin AAD, generados con una implementacion independiente
(Python `cryptography`, `AESCCM(key, tag_length=4)`), para probar `AESCCM` de RoundWhiteDiscKit.

Perfiles: `data_plane` (nonce 13 B, L=2, M=4) y `challenge` (nonce 7 B, L=8, M=4).
Por perfil: 20 positivos (longitudes 1, 15, 29, 35, 51, 57 y otras hasta 120 B) y 10 negativos
(`tag_flip`, `nonce_flip`, `ciphertext_flip`, `truncated`, `wrong_key`, 2 de cada uno), todos verificados
por el propio script como rechazados por la libreria independiente (`expect: auth_failure`).
`reference_vectors`: RFC 3610 no tiene vectores con M=4 (usa M=8 y M=10), asi que se incluye
NIST SP 800-38C Ej. 1 (M=4, nonce 7 B, con AAD 8 B), comprobado contra Python.

## Regenerar
    PY=<scratchpad>/shared_tools/venv/bin/python
    $PY -I Fixtures/tools/gen_ccm_vectors.py [--seed N] [--out ruta.json]
Semilla por defecto 20260101; misma semilla, mismo JSON.

## Test Swift
`pending/CCMVectorTests.swift` va a `Packages/RoundWhiteDiscKit/Tests/RoundWhiteDiscKitTests/`; copiar el JSON a
`Tests/RoundWhiteDiscKitTests/Fixtures/` y anadir `resources: [.copy("Fixtures/ccm_vectors.json")]` al target de tests.
