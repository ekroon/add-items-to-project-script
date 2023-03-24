#!/usr/bin/env bash

# if no agruments are provided, print usage
if [ -z "$1" ]; then
  echo "Usage: add-to-project.sh <org_or_user>/<project_number> <search_query>"
  echo "For url https://github.com/users/ekroon/projects/1, <org_or_user>/<project_number> is: ekroon/1"
  echo "Example: add-to-project.sh ekroon/1 1 is:open is:issue"
  echo "Example: add-to-project.sh ekroon/1 1 is:open is:pr"

  exit 1
fi

# if gh is not install display message to install it
if ! command -v gh &> /dev/null; then
  echo "gh could not be found"
  echo "More information here: https://github.com/cli/cli#installation"

  exit 1
fi

# check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "jq could not be found"
  echo "More information here: https://stedolan.github.io/jq/download/"

  exit 1
fi

# check if first argument is in the correct format "org_or_user/project_number"
if ! [[ "$1" =~ ^[a-zA-Z0-9_-]+/[0-9]+$ ]]; then
  echo "Invalid project format"
  echo "Example: cli/1"

  exit 1
fi

# Get first argument of script and split on '/' to get the project name and number
org_or_user=$(echo "$1" | cut -d'/' -f1)
project_number=$(echo "$1" | cut -d'/' -f2)

# capture the rest of the arguments to the program in a string
search="${*:2}"
# exit if search is empty
if [ -z "$search" ]; then
  echo "No search query provided"
  exit 1
fi

user_query=$(cat <<EOF
query(\$login: String!, \$project_number: Int!) {
  user(login: \$login) {
    projectV2(number: \$project_number) {
      id
    }
  }
}
EOF
)

organization_query=$(cat <<EOF
query(\$login: String!, \$project_number: Int!) {
  organization(login: \$login) {
    projectV2(number: \$project_number) {
      id
    }
  }
}
EOF
)

project_id=$(gh api graphql -F login="$org_or_user" -F project_number="$project_number" -f query="$user_query" 2> /dev/null | jq -r '.data.user.projectV2.id')

if [ "$project_id" = "null" ]; then
  project_id=$(gh api graphql -F login="$org_or_user" -F project_number="$project_number" -f query="$organization_query" 2> /dev/null | jq -r '.data.organization.projectV2.id')
fi

# exit if project_id is still null
if [ "$project_id" = "null" ]; then
  echo "Project not found"
  exit 1
fi

# add -project to $search query
search="$search -project:$org_or_user/$project_number"

# add var to keep track of number of issues added
added=0

while true; do
  # get the issues and node_ids out the results at 'items[].node_id' and split on whitespace in result
  result=$(gh api -X GET search/issues -f q="$search" | jq -r '.items[].node_id')

  # exit if result is empty
  if [ -z "$result" ]; then
    if [ "$added" -eq 0 ]; then
      echo "No results found"
    else
      echo "Added $added issues"
    fi
    exit 1
  fi

  # create template for graphql query from node_id
  mutations=""
  counter=0
  for node_id in $result; do
    # increment counter
    counter=$((counter+1))
    # crate alias for mutation based on counter as string
    alias_node_id="mutation_$counter"
    mutations+=$(cat <<EOF
      $alias_node_id: addProjectV2ItemById(input: {contentId: "$node_id", projectId: "$project_id"}) {
        clientMutationId 
        item {
          content {
            ... on Issue {
              title
            }
            ... on PullRequest {
              title
            }
          }
        }
      }
EOF
  )
  done

  result=$(gh api graphql -f query="mutation { $mutations }")


  titles=$(echo "$result" | jq -r '.data | to_entries[] | .value.item.content.title')
  number_of_titles=$(echo "$titles" | wc -l)
  added=$((added+number_of_titles))

  # every title is on a new line 
  # print it surrounded with quotes and with "Added " prefixed
  echo "$titles" | sed 's/^/"/' | sed 's/$/"/' | sed 's/^/Added /'
done