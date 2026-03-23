import sys

with open('commodore/c128/main.s', 'r') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1
insert_idx = -1

for i, line in enumerate(lines):
    if '// Core System & UI Routines — MUST live in Safe Zone' in line:
        start_idx = i - 1  # Include the === line
    elif 'jmp ($fffc)' in line:
        end_idx = i + 1  # Include the jmp and maybe the newline
    elif 'jmp entry_real' in line:
        insert_idx = i + 1

if start_idx != -1 and end_idx != -1 and insert_idx != -1:
    block = lines[start_idx:end_idx+1]
    del lines[start_idx:end_idx+1]
    
    # Insert block after insert_idx
    lines = lines[:insert_idx] + ['\n'] + block + ['\n'] + lines[insert_idx:]
    
    with open('commodore/c128/main.s', 'w') as f:
        f.writelines(lines)
    print("Code moved successfully.")
else:
    print(f"Failed to find indices: start={start_idx}, end={end_idx}, insert={insert_idx}")
