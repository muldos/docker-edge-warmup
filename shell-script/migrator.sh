#!/bin/bash

# Default values
ARTI_SOURCE_USER="mmyemail@foobar.com"
ARTI_SOURCE_PASSWORD="ChangemMeBefore2025!"

# Function to show script usage
show_help() {
  echo "Usage: ./migrator.sh -s <source_ARTIFACTORY_SOURCE_URL> -t <target_ARTIFACTORY_SOURCE_URL> [-u <source_username>] [-p <source_password>] [-c] [-d <repo_list_file>]"
  echo "Options:"
  echo "  -s <source_ARTIFACTORY_SOURCE_URL>   Set the source Artifactory URL"
  echo "  -t <target_ARTIFACTORY_SOURCE_URL>   Set the target Artifactory URL"
  echo "  -u <source_username>                 Set the source Artifactory username (default: devseopsday@jfrog.com)"
  echo "  -p <source_password>                 Set the source Artifactory password (default: DevSecOpsDay2023!)"
  echo "  -c                                   Create smart remote repositories on the target Artifactory"
  echo "  -d <repo_list_file>                  Download artifacts for repositories listed in the file"
  echo "  -a <artifact_path>                   Download a specific artifact"
  exit 1
}

# Function to get repository information
get_repo() {
  local platform=$1
  local repo_type=$2
  local token=$3
  # Retrieve repository information from the source Artifactory
  local repositories_response=$(curl -s -H "Authorization: Bearer $3" -X GET "https://${1}/artifactory/api/repositories?type=$repo_type")

  # Collect repository information in an array
  local repo_info=()
  while IFS= read -r repo; do
    local packageType=$(echo "$repositories_response" | jq -r --arg repo "$repo" '.[] | select(.key == $repo) | .packageType' | tr '[:upper:]' '[:lower:]')
    repo_info+=("$repo|$repo_type|$packageType")
  done <<< "$(echo "$repositories_response" | jq -r '.[].key')"

  # Return the array
  echo "${repo_info[@]}"
}

# Function to create smart remote repositories on the target Artifactory
create_smart_remote_repo() {
  local repo_output=$1

  # Iterate over the repository information and create smart remotes
  for repo_info in $repo_output; do
    IFS='|' read -r repo repo_type packageType <<< "$repo_info"

    # Convert packageType to lowercase
    packageType=$(echo "$packageType" | tr '[:upper:]' '[:lower:]')

    json_payload=$(cat <<-EOF
{
  "key": "$repo",
  "rclass": "remote",
  "packageType": "$packageType",
  "url": "https://${ARTIFACTORY_SOURCE_URL}/artifactory/$repo",
  "username": "$ARTI_SOURCE_USER",
  "password": "$ARTI_SOURCE_PASSWORD",
  "contentSynchronisation": {
    "enabled": true,
    "statistics": {
      "enabled": true
    }
  }
}
EOF
)

    curl -s -H "Authorization: Bearer $ARTI_TARGET_TOKEN" -X PUT \
      -H "Content-Type: application/json" \
      -d "$json_payload" \
      "https://${ARTIFACTORY_TARGET_URL}/artifactory/api/repositories/$repo"

    echo "Smart remote repo creation for repo '$repo' on instance '$ARTIFACTORY_TARGET_URL' completed."
  done
}

# Function to verify remote repositories
verify_remote_repos() {
  local source_repo_output=$1
  local target_repo_output=$2

  echo "Verifying remote repositories..."

  # Iterate over the source repository information
  for source_repo_info in $source_repo_output; do
    IFS='|' read -r source_repo source_repo_type source_packageType <<< "$source_repo_info"

    # Check if the source repository has a corresponding remote repository on the target
    if ! echo "$target_repo_output" | grep -q "$source_repo"; then
      echo "Error: Remote repository for '$source_repo' not found on the target."
      exit 1
    fi
  done

  echo "All remote repositories from the source have a corresponding remote repository on the target."
}

# Function to download artifacts using Artifact Sync Download API
download_artifacts() {
  local repo_list_file=$1

  # Iterate over the repositories in the list
  while IFS= read -r repo; do
    echo "Downloading artifacts for repository: $repo"

    # Use Artifactory API to list artifacts in the repository recursively

    artifacts_response=$(curl -s -H "Authorization: Bearer $ARTI_SOURCE_TOKEN" \
      "https://${ARTIFACTORY_SOURCE_URL}/artifactory/api/storage/$repo?list&deep=1")
      #echo "artifacts_response: $artifacts_response"

    # Extract artifact paths (files and folders) from the response
    artifact_paths=$(echo "$artifacts_response" | jq -r '.files[].uri' | sed "s|^|$repo|")

    # Iterate over artifact paths and download each artifact
    while IFS= read -r artifact_paths; do
      echo "artifact_paths: $artifact_paths"
      # Use Artifact Sync Download API to download artifacts without returning content to the client
      echo "preloading the cache for "https://${ARTIFACTORY_TARGET_URL}/artifactory/api/download/${artifact_paths}""

      curl -s -H "Authorization: Bearer $ARTI_TARGET_TOKEN" "https://${ARTIFACTORY_TARGET_URL}/artifactory/api/download/${artifact_paths}?content=progress&mark=512"

    done <<< "$artifact_paths"

  done < "$repo_list_file"

  echo "Artifacts downloaded to $temp_dir."
}

download_specific_artifact() {
  local artifact_name=$1

  # Reading the target URL from the artifactory_target.txt file
  local target_urls=($(cat artifactory_target.txt))

  # Extracting repository name and path from the artifact name
  local repo_name=$(echo $1 | cut -d  "/" -f1)
  local repo_path=$(echo $1 | cut -d  "/" -f2-)

  # Array to store background processes
  declare -a processes

  # Iterating over target URLs and starting a background process for each API call
  for url in "${target_urls[@]}"; do
    echo "Downloading specific artifact: $artifact_name from $url"

    # Retrieve SHA-1 values from two sources
    sha1_source1=$(curl -s -k "https://${ARTIFACTORY_SOURCE_URL}/artifactory/api/storage/${artifact_name}" | jq -r '.checksums.sha1')
    sha1_source2=$(curl -s -k "https://${url}/artifactory/api/storage/${artifact_name}" | jq -r '.checksums.sha1')

    echo "sha1_source1: $sha1_source1"
    echo "sha1_source2: $sha1_source2"

    # Check if the SHA-1 values are different
    if [ "$sha1_source1" != "$sha1_source2" ]; then
        echo "SHA-1 values are different."

        # Example: Delete the artifact in the '${artifact_name}-cache' repository
        curl -k -s -X DELETE "https://${url}/artifactory/${repo_name}-cache/${repo_path}"

        # Example: Start a background process for the API call
        curl -k -s "https://${url}/artifactory/api/download/${artifact_name}?content=progress&mark=512" &

    else
        echo "SHA-1 values are identical."
    fi

    # Storing the PID of the process
    processes+=($!)
  done

  # Waiting for all background processes to finish
  wait "${processes[@]}"
}



cleanup_repodata() {
  local target_urls=($(cat artifactory_target.txt))
  local repo_prefix="rmt"            # Prefix of remote repositories to delete

  for url in "${target_urls[@]}"; do
    # Retrieve the list of remote repositories starting with the specified prefix
    local remote_repos=$(curl -k -s -H "Authorization: Bearer $ARTI_SOURCE_TOKEN" "https://${url}/artifactory/api/repositories?packageType=YUM&type=REMOTE" | jq -r '.[].key | select(startswith("'"$repo_prefix"'"))')

    # Iterate through the list of remote repositories and apply DELETE command on repo_data
    for repo_name in $remote_repos; do
      echo "Deleting repodata foler for remote repository: $repo_name"
      curl -k -s -H "Authorization: Bearer $ARTI_SOURCE_TOKEN" -X DELETE "https://${url}/artifactory/${repo_name}-cache/repodata"
    done
  done
}




# Function to create smart remote repositories and download cache content
create_and_cache() {
  local source_repo_list=$(get_repo "${ARTIFACTORY_SOURCE_URL}" local "${ARTI_SOURCE_TOKEN}")
  source_repo_list+=" "$(get_repo "${ARTIFACTORY_SOURCE_URL}" remote "${ARTI_SOURCE_TOKEN}")

  # Create smart remote repositories on the target Artifactory
  create_smart_remote_repo "$source_repo_list" 

  # Verify remote repositories on the target Artifactory
  local target_repo_list=$(get_repo "${ARTIFACTORY_TARGET_URL}" local "${ARTI_TARGET_TOKEN}")
  target_repo_list+=" "$(get_repo "${ARTIFACTORY_TARGET_URL}" remote "${ARTI_TARGET_TOKEN}")
  verify_remote_repos "$source_repo_list" "$target_repo_list"

  # Download artifacts for repositories listed in the file
  if [ -n "$REPO_LIST_FILE" ]; then
    download_artifacts "$REPO_LIST_FILE"
  fi
}

# Parse command line options
while getopts ":s:t:u:p:cd:a:" opt; do
  case $opt in
    s)
      ARTIFACTORY_SOURCE_URL="$OPTARG"
      ;;
    t)
      ARTIFACTORY_TARGET_URL="$OPTARG"
      ;;
    u)
      ARTI_SOURCE_USER="$OPTARG"
      ;;
    p)
      ARTI_SOURCE_PASSWORD="$OPTARG"
      ;;
    c)
      CREATE_REMOTE=true
      ;;
    d)
      DOWNLOAD=true
      REPO_LIST_FILE="$OPTARG"
      ;;
    a)
      ARTIFACT_PATH_SPECIFIC="$OPTARG"
      DOWNLOAD_SPECIFIC=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      show_help
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      show_help
      ;;
  esac
done

# Run the appropriate action based on options
if [ "$CREATE_REMOTE" = true ]; then
  create_and_cache
fi

if [ "$DOWNLOAD" = true ]; then
  download_artifacts "$REPO_LIST_FILE"
fi

# If no options are provided, show the help message
if [ $OPTIND -eq 1 ]; then
  show_help
fi

if [ "$DOWNLOAD_SPECIFIC" = true ]; then
  cleanup_repodata
fi