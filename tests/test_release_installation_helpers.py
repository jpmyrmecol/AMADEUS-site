"""Non-destructive regression checks for version-aware setup completeness.

Run: python tests/test_release_installation_helpers.py
Requires bash. Darwin branch is simulated; this does not test native macOS,
Windows cmd.exe, or PowerShell execution. No installer is executed.
"""
from pathlib import Path
import subprocess,re,tempfile
base=Path(__file__).resolve().parents[1]
new=['gui/addon_gui.py','gui/addon_manager.py','gui/dark_widgets.py','gui/home_drop_routes.py','gui/save_shortcut.py','gui/segmentation_workflow.py']
checks=0
for script,system in [('AMADEUS-Setup.sh','Linux'),('AMADEUS-Setup.command','Darwin')]:
 s=(base/script).read_text();fn=s[s.index('installation_complete()'):s.index('\nlegacy_version()')]
 with tempfile.TemporaryDirectory() as t:
  root=Path(t);names=re.search(r'for file in (.*?); do',fn,re.S)[1].replace('\\\n',' ').split()+['AMADEUS.command','tools/macos_python.sh']
  for n in names:
   p=root/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture')
  (root/'pyproject.toml').write_text('name = "amadeus"\n')
  def run(expect,label):
   global checks
   r=subprocess.run(['bash','-c','uname() { echo '+system+'; }\n'+fn+'\ninstallation_complete "$1"','bash',str(root)],capture_output=True,text=True)
   assert (r.returncode==0)==expect,(script,label,r.returncode,r.stderr)
   checks+=1
  for v in ['1.2.1','v1.2.1','1.1.17']:
   (root/'VERSION').write_text(v);run(True,'older release '+v)
  for v in ['1.2.2','v1.2.2','1.2.3','2.0.0']:
   (root/'VERSION').write_text(v)
   for n in new:(root/n).write_text('module')
   run(True,'complete '+v)
   for n in new:
    p=root/n;p.unlink();run(False,'missing '+n);p.write_text('');run(False,'empty '+n);p.write_text('module')
print('PASS',checks,'version-aware Linux/macOS shell validator checks; uname mocked for macOS branch')

# Ensure the independently maintained Windows validators retain the same additions.
# This is source parity only, not a Windows execution test.
for script in ["AMADEUS-Setup.bat", "AMADEUS-Setup.ps1"]:
    text = (base / script).read_text(encoding="utf-8")
    assert "-ge [Version]'1.2.2'" in text, script
    for helper in new:
        assert helper in text, (script, helper)
print("PASS Windows helper-list and version-guard source parity (not native execution)")
