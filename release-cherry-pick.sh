#!/bin/bash
#set -x
#set -e

MASTER='master'
BRANCH=$(git rev-parse --abbrev-ref HEAD)
PATTERN='\[.*[rR]elease.*\]\|\[.*[bB]ug[fF]ix.*\]'
IGNORECASE="-i"
LOGONLY=''
LOGFORMAT='oneline'

for i in "$@"
do
case $i in
    --master=*)
    MASTER="${i#*=}"
    shift # past argument=value
    ;;
    --branch=*)
    BRANCH="${i#*=}"
    shift # past argument=value
    ;;
    -a|--all)
    PATTERN=".*"
    shift # past argument=value
    ;;
    --tags=*)
    TAGS="${i#*=}"
    PATTERN="\[.*`echo $TAGS | sed 's/,/\.\*\\\\]\\\\|\\\\[\.\*/g'`.*\]"
    shift # past argument=value
    ;;
    --pattern=*)
    PATTERN="${i#*=}"
    shift # past argument=value
    ;;
    --format=*|--pretty=*)
    LOGFORMAT="${i#*=}"
    shift # past argument=value
    ;;
    -l|--log-only=*)
    LOGONLY='yes'
    shift # past argument=value
    ;;
    --no-ignore-case)
    IGNORECASE=''
    shift # past argument=value
    ;;
    *)
    echo Unknown option passed
    exit 1
            # unknown option
    ;;
esac
done

TMPFILE=/tmp/release-cherry-pick.666.$$
git checkout $BRANCH || exit 1

echo Checking for patches to cherry-pick in range $MASTER..$BRANCH

if test -e prevent-cherry-picks; then
    PREVENTED=`cat prevent-cherry-picks | grep -v ^\# | grep -v "^$" | sed -e 's/^/^/g
:a;N;$!ba;s/\n/\\\\|^/g'`
fi 

# Search for comments about cherry-picked commits
PICKED=`git log | grep "cherry picked from commit" | sed "s/.*(cherry picked from commit \(.*\))/\1/"| sed -e 's/^/^/g
:a;N;$!ba;s/\n/\\\\|^/g'`
if test -n "$PREVENTED"; then
    SEP="\\|"
fi
if test -n "$PICKED"; then
    PREVENTED="$PREVENTED""$SEP""$PICKED"
fi
if test -n "$PREVENTED" ; then
    #echo "PREVENTED picks are $PREVENTED"
    REVS=`git rev-list --grep="$PATTERN" $IGNORECASE --cherry-pick --pretty=oneline --reverse --left-only --no-merges $MASTER...$BRANCH |grep -v $PREVENTED`
else 
    REVS=`git rev-list --grep="$PATTERN" $IGNORECASE --cherry-pick --pretty=oneline --reverse --left-only --no-merges $MASTER...$BRANCH`
fi
if test -n "$REVS" ; then 
    echo "The following commits can be cherry-picked:"
    echo "$REVS" | while read i; do
        R=`echo $i | sed "s/^\([0-9a-f]\+\)\s\+.*$/\1/"`
        git log --pretty=$LOGFORMAT $R^..$R
    done
    if test -n "$LOGONLY" ; then 
        exit 0
    fi

    read -p "Shall we pick all the above cherries? [A(ll)/N(one)/P(ick individually)]" answer
    while true
    do
	case $answer in
	    [aA]* )
		
		if test -n "$PREVENTED"; then
		    git rev-list --grep="$PATTERN" $IGNORECASE --cherry-pick --reverse --left-only --no-merges $MASTER...$BRANCH | grep -v $PREVENTED | xargs git cherry-pick -x -s
		else
		    git rev-list --grep="$PATTERN" $IGNORECASE --cherry-pick --reverse --left-only --no-merges $MASTER...$BRANCH | xargs git cherry-pick -x -s
		fi
		break;;
	    [nN]* )
		echo "Quitting..."
		exit 1;;
	    [pP]* )
		OIFS="$IFS"
		NIFS=$'\t\n'
		export IFS=$NIFS
		for i in $REVS; do
		    export IFS="$OIFS"
		    processing=1
		    CHERRY=`echo $i | sed "s/^\([0-9a-f]\+\)\s\+.*$/\1/"`
		    while test $processing; do
			echo "Next patch is: $i"
			read -p "Shall we pick it? Y(es)/N(o)/S(how)" answer
			case $answer in
			    [yY]* )
				git cherry-pick -x -s $CHERRY
				processing=0
				break;;
			    [nN]* )
				read -p "Add sha1 to prevent-cherry-picks? Y(es)/N(o)" answer
				case $answer in
				    [yY]* )
					echo $CHERRY >> prevent-cherry-picks
					git add prevent-cherry-picks
					echo added $CHERRY to prevent-cherry-picks and marked it for committing.
					break
					;;
				esac
				processing=0
				;;
			    [sS]* )
				git show $CHERRY
				;;
			    * )     echo "Dude, just enter Y, N, or S please."; break ;;
			esac
		    done
		    export IFS="$NIFS"
		    done
		export IFS="$OIFS"
		break
		;;
	    * )     echo "Dude, just enter A, N, or P, please."; exit 1 ;;
	esac
    done
else
    echo "Nothing to cherry-pick..."
    exit 0
fi
