check_empty_argument(){
  if [ -z "$1" ] ; then
      echo "Empty Arugment Passed"
      exit 40
  fi
}

function set_python_version(){
    command -v python3 >/dev/null 2>&1 && PYTHON="python3"
    if [[ -z $PYTHON ]]; then
        command -v python >/dev/null 2>&1 && PYTHON="python"
        if [[ -z $PYTHON ]]; then
            echo "Python not found"
            return -1
        fi
    fi
}

function read_json_key(){
    local text=$1
    local key=$2
    set_python_version

    #replace dots convention of A.B.C to ["A"]["B"]["C"], which is needed by python to read nested json key using multi-dimensional array
    key="${key//./\"][\"}"      #replaces dots with square brackets and ""
    key="[\"$key\"]"            #adds leading and ending brackets

    echo "$text" | $PYTHON -c 'import sys, json; print(json.load(sys.stdin)'$key')'
}

set_python_version