# Artifactory Migrator Script

The Artifactory Migrator Script is a Bash script designed to facilitate the migration of artifacts between two Artifactory instances. It provides functionality to create smart remote repositories on the target Artifactory, verify remote repositories, download artifacts, and perform specific artifact downloads.

## Prerequisites

Before using this script, ensure the following:

- Both the source and target Artifactory instances are accessible over the network.
- You have appropriate permissions to access and modify repositories on both instances.
- You have `curl` and `jq` installed on your system.

## Usage

To use the script, follow the steps below:

1. Clone or download the script to your local machine.

2. Make the script executable by running:

    ```bash
    chmod +x migrator.sh
    ```

3. Run the script with the desired options:

    ```bash
    ./migrator.sh -s <source_ARTIFACTORY_SOURCE_URL> -t <target_ARTIFACTORY_SOURCE_URL> [-u <source_username>] [-p <source_password>] [-c] [-d <repo_list_file>] [-a <artifact_path>]
    ```

    - `-s <source_ARTIFACTORY_SOURCE_URL>`: Set the source Artifactory URL.
    - `-t <target_ARTIFACTORY_SOURCE_URL>`: Set the target Artifactory URL.
    - `-u <source_username>`: Set the source Artifactory username (default: devseopsday@jfrog.com).
    - `-p <source_password>`: Set the source Artifactory password (default: DevSecOpsDay2023!).
    - `-c`: Create smart remote repositories on the target Artifactory.
    - `-d <repo_list_file>`: Download artifacts for repositories listed in the file.
    - `-a <artifact_path>`: Download a specific artifact.

4. Follow the prompts and instructions provided by the script.

## Examples

### Create Smart Remote Repositories

To create smart remote repositories on the target Artifactory, use the following command:

```bash
./migrator.sh -s <source_ARTIFACTORY_SOURCE_URL> -t <target_ARTIFACTORY_SOURCE_URL> -c
```

### Download Artifacts
To download artifacts for repositories listed in a file, use the following command:

```bash
./migrator.sh -s <source_ARTIFACTORY_SOURCE_URL> -t <target_ARTIFACTORY_SOURCE_URL> -d <repo_list_file>
```

### Download Specific Artifact
To download a specific artifact, use the following command:

```bash
./migrator.sh -s <source_ARTIFACTORY_SOURCE_URL> -t <target_ARTIFACTORY_SOURCE_URL> -a <artifact_path>
```