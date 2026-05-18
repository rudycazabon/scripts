import contextlib
import os
import glob
import argparse
import subprocess
import sys

@contextlib.contextmanager
def CurrentWorkingDirectory(dir):
    """Context manager that sets the current working directory to the given
    directory and resets it to the original directory when closed."""
    curdir = os.getcwd()
    os.chdir(dir)
    try: yield
    finally: os.chdir(curdir)

class InstallContext:
    def __init__(self, args):
        self.searchDir = os.path.normpath(
            os.path.join(os.path.abspath(os.path.dirname(__file__))))

parser = argparse.ArgumentParser()
args = parser.parse_args()

context = InstallContext(args)


def CheckGit(dir):
    with CurrentWorkingDirectory(dir):
        # Find all items (files and directories)
        all_items = glob.glob('*')

        # Filter for directories
        directories = [item for item in all_items if os.path.isdir(item)]
        print(f"Directories in current directory: {directories}")

        if(os.path.exists(dir)):
            Run(['git','fetch'])
            Run(['git','status'])


def Run(cmd):

    with subprocess.Popen(cmd, stdout=subprocess.PIPE, bufsize=1, universal_newlines=True) as p:
        for line in p.stdout:
            print(line, end='', flush=True) # Print each line as it's received
        
        # Wait for the process to complete and get the return code
        p.wait() 
        if p.returncode != 0:
            print(f"Subprocess exited with error code {p.returncode}", file=sys.stderr)
    


with CurrentWorkingDirectory(os.getcwd()) as srcDir:
    # Find all items (files and directories)
    all_items = glob.glob('*')

    # Filter for directories
    directories = [item for item in all_items if os.path.isdir(item)]
    print(f"Directories in current directory: {directories}")

    for d in directories:
        with CurrentWorkingDirectory(d) as innerDir:
            intro = '>'*10
            outro = '<'*10
            print(f'\n\033[032m',intro,'Entering: {}\033[0m'.format(d))
            if(os.path.exists('.git')):
                print("Checking git.")
                Run(['git','remote','-v'])
                Run(['git','fetch'])
                Run(['git','status'])
            print(f'\033[032m',intro,'Exiting: {}\033[0m\n'.format(d))

    