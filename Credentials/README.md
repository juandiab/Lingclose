# Credentials (no versionado)

Aquí se coloca, solo en el Mac de Juampa, el archivo `lingo-identity.json` con la identidad de app Lingo y la clave pública de firma del parche, en el formato JSON que acepta `AppIdentities.install(json:)` de RoundWhiteDiscKit, extendido con `productTypes` y `patchSigningPublicKeyHex` (ver `docs/FORK_RWDK.md` §2 y la tarea T-05).

```json
{
  "format": 1,
  "curve": "P-256",
  "identities": [
    {
      "label": "lingo-v3",
      "productTypes": [9],
      "securityVersions": [3],
      "privateKeyHex": "<32 bytes>",
      "certificateHex": "<162 bytes, cabecera 03 01>",
      "patchSigningPublicKeyHex": "<65 bytes, 04 ...>"
    }
  ]
}
```

Origen de los valores: `LingoCredentials.java` de Juggluco 11.5.4 (`APP_PRIVATE` líneas 29-33, `APP_CERTIFICATE` 35-50, `PATCH_SIGNING_PUBLIC` 52-59). Juampa autorizó su uso personal el 2026-10-27. No se copian a ningún documento, log ni commit.

En tiempo de ejecución el archivo se carga una sola vez, se valida (`AppIdentity` comprueba que la clave pública del certificado coincide con la privada) y se guarda en el Keychain del dispositivo con `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. El JSON se borra del bundle de la app antes de instalar en el iPhone; la app lo recibe por AirDrop o Archivos la primera vez.
