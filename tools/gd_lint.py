"""A structural sanity check for GDScript: the class of error that stops a
file parsing. Not a full parser - it catches indentation faults, empty
blocks, unbalanced brackets and stray spaces-for-tabs."""
import sys, re, os

FILES = sys.argv[1:]
BLOCK_END = re.compile(r":\s*(#.*)?$")

def check(path):
    problems = []
    lines = open(path, encoding="utf-8").read().split("\n")

    depth_stack = []
    open_brackets = 0
    prev_indent = 0
    prev_opens_block = False
    prev_lineno = 0
    prev_text = ""
    continued = False
    stmt_indent = 0

    for i, raw in enumerate(lines, 1):
        if raw.strip() == "":
            continue
        was_continued = continued
        continued = raw.rstrip().endswith("\\")
        if was_continued:
            # A wrapped condition. Its indent is cosmetic, and only the LAST
            # physical line can open a block - which the code below handles
            # on the next pass because prev_indent is left alone.
            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw)
            open_brackets += code.count("(") + code.count("[") + code.count("{")
            open_brackets -= code.count(")") + code.count("]") + code.count("}")
            if not continued and BLOCK_END.search(raw) and open_brackets == 0:
                prev_opens_block = True
                prev_lineno = i
                prev_text = raw.strip()
                prev_indent = stmt_indent
            continue
        stmt_indent = len(raw) - len(raw.lstrip("\t"))
        # --- indentation must be tabs only ---
        lead = len(raw) - len(raw.lstrip("\t"))
        after = raw[lead:]
        if after.startswith(" ") and not after.lstrip().startswith("#"):
            problems.append(f"{i}: indented with SPACES after {lead} tab(s): {raw[:60]!r}")
        indent = lead

        stripped = raw.strip()
        is_comment = stripped.startswith("#")

        # --- a line ending in ':' must be followed by a deeper line ---
        if prev_opens_block and not is_comment:
            if indent <= prev_indent:
                problems.append(
                    f"{prev_lineno}: block opened by {prev_text[:50]!r} "
                    f"but line {i} is not indented deeper "
                    f"({prev_indent} -> {indent} tabs)")
            prev_opens_block = False
        elif prev_opens_block and is_comment:
            pass  # comment may sit at any depth; keep waiting

        if open_brackets == 0 and not is_comment and BLOCK_END.search(raw):
            # not a dict literal line or a type hint like  var x: int = 1
            if not re.search(r"^\s*(var|const)\s+\w+\s*:", raw):
                prev_opens_block = True
                prev_indent = indent
                prev_lineno = i
                prev_text = stripped

        # --- bracket balance ---
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw)
        code = re.sub(r"'(?:[^'\\]|\\.)*'", "''", code)
        code = code.split("#")[0]
        open_brackets += code.count("(") + code.count("[") + code.count("{")
        open_brackets -= code.count(")") + code.count("]") + code.count("}")
        if open_brackets < 0:
            problems.append(f"{i}: more closing than opening brackets")
            open_brackets = 0

    if prev_opens_block:
        problems.append(f"{prev_lineno}: file ends with an unclosed block: {prev_text[:50]!r}")
    if open_brackets != 0:
        problems.append(f"end of file: {open_brackets} bracket(s) left open")
    return problems

bad = 0
for f in FILES:
    p = check(f)
    name = os.path.basename(f)
    if p:
        bad += 1
        print(f"--- {name}")
        for x in p:
            print("    " + x)
    else:
        print(f"ok  {name}")
sys.exit(1 if bad else 0)
