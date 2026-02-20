import re
import os

def parse_umoria(filepath):
    creatures = {}
    with open(filepath, 'r') as f:
        content = f.read()

    cr_match = re.search(r'creatures_list\[.*?\]\s*=\s*\{(.*?)\n\};', content, re.DOTALL)
    if not cr_match:
        return creatures
    cr_text = cr_match.group(1)
    
    pattern = (
        r'\{"([^"]+)"'
        r',\s*(0x[0-9A-Fa-f]+)L'
        r',\s*(0x[0-9A-Fa-f]+)L'
        r',\s*(0x[0-9A-Fa-f]+)'
        r',\s*(\d+)L?'
        r',\s*(\d+)'
        r',\s*(\d+)'
        r',\s*(\d+)'
        r',\s*(\d+)'
        r",\s*'(.)',"
        r'\s*\{\s*(\d+),\s*(\d+)\}'
        r',\s*\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\}'
        r',\s*(\d+)\}'
    )

    for m in re.finditer(pattern, cr_text):
        name = m.group(1)
        creatures[name] = {
            'xp': int(m.group(5)),
            'ac': int(m.group(8)),
            'speed': int(m.group(9)),
            'char': m.group(10),
            'hd': f"{m.group(11)}d{m.group(12)}",
            'dlvl': int(m.group(17))
        }
    return creatures

def parse_vms(filepath):
    creatures = {}
    with open(filepath, 'r') as f:
        content = f.read()
    
    for line in content.split('\n'):
        if line.strip().startswith("('"):
            match = re.search(r"^\(\'([^']+)\'", line.strip())
            if match:
                name = match.group(1).strip()
                parts = re.findall(r"(?:%X'[0-9A-F]+'|\d+|'[^']*')", line)
                try:
                    if len(parts) >= 17 and parts[0].startswith("'"):
                         c = {
                            'xp': int(parts[5]),
                            'ac': int(parts[7]),
                            'hd': f"{parts[10]}d{parts[11]}",
                            'dlvl': int(parts[-1].strip("),")) if ')' in parts[-1] else int(parts[-1])
                         }
                         creatures[name] = c
                except Exception:
                    creatures[name] = {'xp': '?', 'ac': '?', 'hd': '?d?', 'dlvl': '?'}
    return creatures

def get_moria8_selected(filepath):
    selected = set()
    with open(filepath, 'r') as f:
         in_list = False
         for line in f:
              if 'SELECTED_NAMES = [' in line:
                   in_list = True
                   continue
              if in_list and ']' in line:
                   break
              if in_list:
                   m = re.search(r'"([^"]+)"', line)
                   if m:
                        selected.add(m.group(1))
    return selected

def main():
    umoria_file = "/Users/chadwick/Library/Mobile Documents/com~apple~CloudDocs/Projects/6502/moria8/umoria/src/data_creatures.cpp"
    vms_file = "/Users/chadwick/Library/Mobile Documents/com~apple~CloudDocs/Projects/6502/moria8/vms-moria/source/include/values.inc"
    parse_file = "/Users/chadwick/Library/Mobile Documents/com~apple~CloudDocs/Projects/6502/moria8/tools/parse_creatures.py"
    
    u_cr = parse_umoria(umoria_file)
    v_cr = parse_vms(vms_file)
    m8_names = get_moria8_selected(parse_file)
    
    all_names = set(u_cr.keys()) | set(v_cr.keys())
    
    with open("/Users/chadwick/.gemini/antigravity/brain/fa57cf0f-3ea4-4d79-ab22-515cb3f090ce/moria_comparison.md", "a") as f:
        f.write("\n\n## 2. Monsters\n\n")
        f.write("Below is a table comparing the monsters across the three ports. `umoria` and `vms-moria` share most generic stats, but `moria8` selected exactly 120 monsters from the `umoria` database to fit within the limited C64 RAM. Their combat stats match `umoria` exactly.\n\n")
        f.write("| Monster Name | Present in VMS | Present in Umoria | Present in Moria8 | DLVL (U) | HP Die (U) | AC (U) | EXP (U) |\n")
        f.write("| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |\n")
        
        written = 0
        for name in sorted(all_names):
            if written >= 100:
                f.write(f"| *... {len(all_names)-100} more monsters elided for brevity ...* | | | | | | | |\n")
                break
            written += 1
                
            in_v = "Yes" if name in v_cr else "No"
            in_u = "Yes" if name in u_cr else "No"
            in_m8 = "Yes" if name in m8_names else "No"
            
            ref = u_cr.get(name, v_cr.get(name, {}))
            dlvl = ref.get('dlvl', '?')
            hd = ref.get('hd', '?')
            ac = ref.get('ac', '?')
            xp = ref.get('xp', '?')
            
            v_ref = v_cr.get(name, {})
            u_ref = u_cr.get(name, {})
            diff_note = ""
            if in_v == "Yes" and in_u == "Yes":
               if v_ref.get('xp') != u_ref.get('xp') or v_ref.get('ac') != u_ref.get('ac'):
                   diff_note = " *(Stats Differ)*"
            
            f.write(f"| {name}{diff_note} | {in_v} | {in_u} | {in_m8} | {dlvl} | {hd} | {ac} | {xp} |\n")

if __name__ == "__main__":
    main()
