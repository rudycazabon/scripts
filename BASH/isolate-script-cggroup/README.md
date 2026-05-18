# Isolate Script

This script creates an isolated environment using Linux namespaces and cgroups, executes a provided Bash script, and then cleans up the environment. It ensures that any changes made within the isolated environment do not affect the host system.

## How It Works

1. **Argument Check**: The script checks if a Bash script file is provided as an argument.
2. **File Existence Check**: It verifies if the provided file exists.
3. **Cgroup Creation**: A cgroup is created to limit the number of processes to 50.
4. **Namespace Creation**: The script creates new PID and UTS namespaces using `unshare`.
5. **Hostname Change**: The hostname is changed to `isolated_env`.
6. **Temporary File System Isolation**: A new `tmpfs` is mounted to isolate the temporary file system.
7. **Script Execution**: The provided script is executed within the isolated environment.
8. **Cleanup**: The temporary file system is unmounted and the cgroup is removed after execution.

## Usage

1. Save the `isolate.sh` script and make it executable:
    ```sh
    chmod +x isolate.sh
    ```

2. Create a sample Bash script, e.g., `test_script.sh`:
    ```bash
    #!/bin/bash
    echo "This is a script running in an isolated environment"
    touch /tmp/testfile
    ls /tmp
    ```

3. Execute the `isolate.sh` script, passing the sample script as an argument:
    ```sh
    ./isolate.sh test_script.sh
    ```

## Example

Given a script `test_script.sh`:

```bash
#!/bin/bash
echo "This is a script running in an isolated environment"
touch /tmp/testfile
ls /tmp
```

Running the following command:

```bash
./isolate.sh test_script.sh
```

Will output:
```
This is a script running in an isolated environment
testfile
Isolated environment finished and cleaned up, including cgroup.
```

The changes made within the isolated environment (like creating `/tmp/testfile`) will not affect the host system's `/tmp` directory.

## Notes
The script uses unshare to create new namespaces and mount to create an isolated file system.
Cgroups are used to limit the number of processes to 50. You can adjust this limit as needed.
The isolated environment is cleaned up after the script execution, ensuring no residual changes affect the host system.





