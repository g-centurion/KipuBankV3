#!/usr/bin/env python3
import os
import re
from pathlib import Path

ROOT = Path('/home/sonic/KipuBankV3_TP4')
DOC = ROOT / 'docs' / 'Informe_Educativo_KipuBankV3_TP4.md'
FLOW = ROOT / 'FLOW_DIAGRAMS.md'
OUT = ROOT / 'docs' / 'Informe_Educativo_KipuBankV3_TP4.ascii.md'


def read_text(p: Path) -> str:
    with p.open('r', encoding='utf-8') as f:
        return f.read()


def extract_ascii_blocks(flow_md: str) -> dict:
    # Map section titles to code blocks (first code block under each matching h2)
    blocks = {}
    lines = flow_md.splitlines()
    current_title = None
    in_code = False
    buf = []
    for i, line in enumerate(lines):
        if line.startswith('## '):
            # Save previous block if any
            if current_title and buf:
                blocks[current_title] = '\n'.join(buf).strip('\n')
                buf = []
            title = line[3:].strip()
            current_title = title
            in_code = False
            continue
        if current_title:
            if line.strip().startswith('```') and not in_code:
                in_code = True
                buf = []
                continue
            elif line.strip().startswith('```') and in_code:
                in_code = False
                # keep only first code block per section
                # Next code blocks are ignored for simplicity
                continue
            if in_code:
                buf.append(line)
    # save last
    if current_title and buf:
        blocks[current_title] = '\n'.join(buf).strip('\n')
    return blocks


def normalize_title(s: str) -> str:
    # Basic normalization: lower, remove punctuation, accents naive
    import unicodedata
    s = s.strip()
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode('ascii')
    s = re.sub(r'[^a-zA-Z0-9 ]+', ' ', s)
    s = re.sub(r'\s+', ' ', s).strip().lower()
    return s


def build_title_mapping(blocks: dict) -> dict:
    # Map README headings to FLOW titles
    title_map = {
        '1 flujo general del sistema': '1. Flujo General del Sistema',
        '2 deposito de eth secuencia': '2. Flujo Detallado: Dep\u00f3sito de ETH',
        '3 deposito erc20 con swap': '3. Flujo Detallado: Dep\u00f3sito con Swap',
        '4 retiro arbol de decision': '4. Flujo Detallado: Retiro',
        '5 validacion de oraculo getethpriceinusd': '5. Validaci\u00f3n de Precios (Oracle Check)',
        '6 patron cei checks effects interactions': '9. Secuencia de Seguridad: CEI Pattern',
        '7 gestion de roles accesscontrol': '12. Gesti\u00f3n de Roles (AccessControl)',
        '8 timelock programar operacion': '13. Timelock: Proponer, Programar y Ejecutar',
        '9 catalogo de tokens': '10. Cat\u00e1logo de Tokens: Alta/Actualizaci\u00f3n',
        '10 ciclo completo de transaccion': '6. Ciclo de Vida de una Transacci\u00f3n',
        # Ap\u00e9ndice A sin titulo numerado
        'apendice a diagrama simplificado': '1. Flujo General del Sistema',
    }
    # Build normalized mapping to ascii blocks
    norm_blocks = {}
    # Build reverse: normalized FLOW title -> ascii
    norm_flow = {normalize_title(k): v for k, v in blocks.items()}
    for readme_title, flow_title in title_map.items():
        norm_flow_title = normalize_title(flow_title)
        if norm_flow_title in norm_flow:
            norm_blocks[readme_title] = norm_flow[norm_flow_title]
    return norm_blocks


def convert_doc(md: str, ascii_map: dict) -> str:
    lines = md.splitlines()
    out = []
    last_heading = ''
    i = 0
    while i < len(lines):
        line = lines[i]
        # capture headings like '#### 1. ...' or '## Ap\u00e9ndice A: ...'
        if re.match(r'^#{2,6} ', line):
            htxt = re.sub(r'^#{2,6} ', '', line).strip()
            last_heading = normalize_title(htxt)
            out.append(line)
            i += 1
            continue
        if line.strip().startswith('```mermaid'):
            # skip until closing ```
            j = i + 1
            while j < len(lines) and not lines[j].strip().startswith('```'):
                j += 1
            # find ascii by last_heading
            ascii_key = last_heading
            ascii_block = ascii_map.get(ascii_key)
            if ascii_block:
                out.append('```')
                out.extend(ascii_block.splitlines())
                out.append('```')
            # else: drop the mermaid block silently
            i = j + 1
            continue
        else:
            out.append(line)
            i += 1
    return '\n'.join(out) + '\n'


def main():
    flow_md = read_text(FLOW)
    edu_md = read_text(DOC)
    blocks = extract_ascii_blocks(flow_md)
    ascii_map = build_title_mapping(blocks)
    converted = convert_doc(edu_md, ascii_map)
    OUT.write_text(converted, encoding='utf-8')
    print(f"Wrote ASCII-converted markdown to: {OUT}")


if __name__ == '__main__':
    main()
