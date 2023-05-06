#!/bin/bash

# This script is designed to manage PDF files of scientific papers downloaded from arXiv.
# It provides functions to load, find, and manage papers based on their priority and content.

# Utility function to sanitize filenames (remove extra characters)
sanitize_filename() {
    echo "${1// \(*\)/}"
}

# Load papers from a given path
load_papers() {
    
    local all=0
    local force=""
    local target=""
    local minutes="-15"

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -t|--target) target="$2"; shift ;;
            -a|--all) all=1 ;;
            -f|--force) force="-f" ;;
            -m|--minutes) minutes="-$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
    done

    if [[ "$target" == "" ]]; then
        target="$HOME/Downloads"
    fi
    echo "Chosen target: $target"

    if [[ $all == 1 ]]; then
        find "$target" -name '*.pdf' | while read line; do
            process_pdf $line $force
        done
    else
        find "$target" -name '*.pdf' -mmin $minutes | while read line; do
            process_pdf $line $force
        done
    fi
}

process_pdf() {
    if [[ $1 == "" ]]; then
        echo "No arg to proc_pdf provided, suiciding"
        return 2
    fi

    if [[ $1 == "-f" ]]; then
        echo "No file (or empty filename?) provided, aborting"
        return 3
    fi

    local filename=$(basename $1)
    local file_san=$(sanitize_filename $filename)
    local arxiv_id=$(echo "$file_san" | cat | head -c -5)

    local force=0
    if [[ $2 == "-f" ]]; then
        force=1
    fi


    local article_name=$(determine_article_name $arxiv_id)

    local path_to_folder="$HOME/papers/storage/$article_name"

    if [ -d "$path_to_folder" ]; then
        if [ $force -eq 1 ]; then
            rm -rf $path_to_folder
        else
            echo "Warning: file was already loaded. If you want to force overwrite, use -f option"
            return 1
        fi
    fi

    echo "$article_name"
    local path_to_pdf="$path_to_folder/$article_name.pdf"

    mkdir -p $path_to_folder
    cp $1 $path_to_pdf

    # add the access file, with the correct content
    echo "$(date +%s)" > "$path_to_folder/.access"

    # now lets make a text file, with the name article_name.txt
    pdftotext -layout $path_to_pdf "$path_to_folder/$article_name.txt"

    # and we are done! great, lolz!
}

is_valid_paper_id() {
    local id="$1"
    local regex_new='^[0-9]{4,5}\.[0-9]{5}$'
    local regex_old='^[0-9]{2}[0-9]{4}$'

    if [[ "$id" =~ $regex_new ]] || [[ "$id" =~ $regex_old ]]; then
        return 0
    else
        return 1
    fi
}

determine_article_name() {
    local inp=${1// /_}
    # if the parameter is not a valid arxiv id -> return just the parameter
    if [[ $(is_valid_paper_id $1) == 1 ]]; then
        echo $inp
    fi

    # call to the arxiv API to get some info about paper
    # While we could have called it only once, it has some issues when there is at least one id in the list that is invalid, so to avoid this issue we just call for each "qualified" article this thing directly. Maybe in the future we will call actual google scholar for the article name or something, idk
    #
    local info=$(wget -qO- "http://export.arxiv.org/api/query?id_list=$1")

    local title=$(echo "$info" | awk -F'<title>|</title>' '/<entry>/,/<\/entry>/ { if ($2) print $2; }')

    # check that title is not empty
    if [[ $title == "" ]]; then
        echo $inp
    fi

    title=${title// /_}
    # remove special chars
    title=${title//[^[:alnum:]_]/}

    echo $title
}

# this function echoes all the folders that correspond with the current query.
find_papers() {
    local pattern=$1
    
    local book=0
    local paper=0
    shift
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -t|--target) target="$2"; shift ;;
            -b|--book) book=1 ;;
            -p|--paper) paper=1 ;;
            *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
    done

    local num_accesses=()
    local accesses=()
    local data=()


#    find "$HOME/papers" -type f -name "*.txt" -not -path "*/_*/*/*" | while read line; do
    grep -li "\b$pattern" $HOME/papers/*/*/*.txt | while read line; do
        
        local file_size=$(du -k "$line" | cut -f 1)
        if [[ $book == 1 && $file_size -le 300 ]]; then
            continue
        fi
        if [[ $paper == 1 && $file_size -ge 301 ]]; then
            continue
        fi
        local num_inside=$(grep -ois "\b$pattern" "$line" | wc -l)

        local nitm2=$(echo "$line" | grep -ois "${pattern// /_}" | wc -l)
        let num_in_the_name=$nitm1+$nitm2

        if [[ $num_inside -le 3 && num_in_the_name == 0 ]]; then 
            continue
        fi
        # now the score can be computed via a really hard formula
        # 100 * num_in_the_name + last_access(rank) * 103 + second_to_last_access(rank) * 71 + third_to_last_access(rank) * 42 + num_inside(rank) * 11 + num_accesses(rank) * 7
        # Hence we need to store all the access time, and sort them, and then do a lot of searches all over them. Might be slow? Sure, but good enough.. If perf issues - will rewrite in rust :)

        local ac_file="$(dirname "$line")/.access"
        while IFS= read -r other; do
            accesses+=("$other")
        done < <(tail -n 5 $ac_file)
        
        local last_access=$(tail -n 1 $ac_file)

        local num=$(cat $ac_file | wc -l)

        data+=( "$line;$num_inside;$num_in_the_name;$last_access;$num" )

        num_accesses+=( "$num" )
    done

    accesses=($(printf '%s\n' "${accesses[@]}" | sort -u | sort -nr))
    num_accesses=($(printf '%s\n' "${num_accesses[@]}" | sort -u | sort -n))

    output=()
    # now iterate again all over data
    for x in "${data[@]}"; do
        process_line $x
    done

    output=$(printf '%s\n' "${output[@]}" | sort -t' ' -k2 -n -r)

    local opts=()
    local p_pathes=()
    local p_access=()
    echo "$output" | while read line; do
        local thing="$(echo "$line" | cut -d "." -f1)"
        p_pathes+="$thing.pdf"
        p_access+=( "$(dirname $thing)/.access" )
        thing=$(basename $thing)
        opts+=( ${thing//_/ } )

    done

    createmenu "${#opts[@]}" "${opts[@]}"

    if [[ chosen_paper == -1 ]]; then
        echo "Exiting due to issues with menu"
        exit 7
    fi
    
    echo "${p_access[$chosen_paper]}"

    echo "$(date +%s)" >> "${p_access[$chosen_paper]}"
    f_pdf_open "${p_pathes[$chosen_paper]}"
}

process_line() {
    local inp=($(awk -v delim=";" '{n=split($0,a,delim); for(i=1;i<=n;i++) print a[i]}' <<< "$x"))

    local name=${inp[1]}

    local num_inside=${inp[2]}
    local num_in_the_name=${inp[3]}
    local last_access=${inp[4]}
    local access_num=${inp[5]}

    to_search=$access_num
    local accesses_num_rank=$(get_index "$num_accesses")

    to_search=$last_access
    local lar=$(get_index "$accesses")

    local score=0
    let "score = 500 * $num_in_the_name - $lar * 500 + $num_inside * 10 + $accesses_num_rank * 100"
    
    output+=( "$name $score" )
}

f_pdf_open() {
    echo "!!!$1"
    if [[ $1 == "" || $1 == ".pdf" ]]; then
        return 1
    fi

    echo "opening: $1"
    sioyek $1
}

createmenu () {
  arrsize=$1
  if [[ $arr_size == 1 ]]; then
    chosen_paper=0
    return 0
  fi

  chosen_paper=-1
  select option in "${@:2}"; do
    if [ "$REPLY" -eq "$arrsize" ];
    then
      echo "Exiting..."
      break;
    elif [ 1 -le "$REPLY" ] && [ "$REPLY" -le $((arrsize-1)) ];
    then
      echo "You selected $option which is option $REPLY"
      chosen_paper=$REPLY
      break;
    else
      echo "Incorrect Input: Select a number 1-$arrsize"
    fi
  done
}

get_index() {
    local array=("$@")  # Copy the arguments into a local array
    local element="$to_search"  # Get the last argument as the element to search for

    awk -v element="$element" '{
        for (i=1; i<=NF; i++) {
            if ($i == element) {
                print i-1;
                exit;
            }
        }
        print 0;
    }' <(printf '%s\n' "${array[@]}")
}

alias pfi="find_papers"
alias plo="load_papers"
