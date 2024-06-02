import subprocess
import os
import os.path as path

taskdir = 'task03-add-sub-cmp'

bin_files = [x for x in os.listdir('files') if not x.endswith('.asm')]

exepath = path.abspath(path.join('.', taskdir, 'decoder.exe'))

for bin_file in bin_files:
    bin_file = path.abspath(path.join('.', 'files', bin_file))
    res = subprocess.run("%s %s > out.asm" % (exepath, bin_file), shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res.returncode != 0:
        print('FAILED %s' % bin_file)
        continue
    subprocess.run("nasm out.asm")
    res = subprocess.run("fc.exe /b out %s" % bin_file, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res.returncode != 0:
        print('FAILED %s' % bin_file)
    else:
        print('OK     %s' % bin_file)
    os.remove('out')
    os.remove('out.asm')

# os.remove('out')
# os.remove('out.asm')
    
