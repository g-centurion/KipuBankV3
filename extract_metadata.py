#!/usr/bin/env python3
import json
import os

# Leer el artifact de Foundry
with open('out/KipuBankV3_TP4.sol/KipuBankV3.json', 'r') as f:
    artifact = json.load(f)

# Obtener metadata
metadata = artifact['metadata']
if isinstance(metadata, str):
    metadata = json.loads(metadata)

# Para Blockscout necesitamos agregar el contenido de cada archivo fuente
for source_path, source_info in metadata['sources'].items():
    # Convertir la ruta del formato de metadata a ruta del sistema de archivos
    file_path = source_path
    
    # Intentar leer el archivo
    if os.path.exists(file_path):
        with open(file_path, 'r', encoding='utf-8') as src_file:
            source_info['content'] = src_file.read()
    else:
        print(f"⚠ Advertencia: No se pudo leer {file_path}")

# Guardar el metadata completo con contenido de archivos
with open('standard-input.json', 'w') as f:
    json.dump(metadata, f, indent=2)

print(f"✓ Standard JSON Input generado: standard-input.json ({len(json.dumps(metadata))} bytes)")
print(f"✓ Archivos fuente incluidos: {len(metadata['sources'])}")
