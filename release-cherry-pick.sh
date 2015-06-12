#!/bin/bash
#set -x
#set -e

FROM='master'
TO=$(git rev-parse --abbrev-ref HEAD)
TAGS='release,bugfix'
PATTERN=''
IGNORECASE="-i"
LOGONLY=''
LOGFORMAT='oneline'

USAGE="\
USAGE
        release-cherry-pick.sh  [--from=F] [--to=T]
                                [-l|--log-only]
                                [--format=FORMAT]
                                [--tags=tag1,tag2,...,tagn]
                                [--pattern=P]
                                [-a|--all]
                                [--no-ignore-case]
                                [-h|--help]

OPTIONS

        --to=T
            Sets the target branch where cherry-picked commits go to to T.
            The default for T is the current branch.

        --from=F
            Sets the origin branch where cherry-picked commits come from to F
            The default for M is 'master'

        -l, --log-only
            Will only print out a log of the matchinh commits and
            not try to do actual cherry-picking.

        --format=FORMAT
            Will set the log format to FORMAT. This can be anything that is
            accepted by 'git log --format='.
            The default for FORMAT is 'oneline'.

        --tags=tag1,tag2,...,tagn
            Will only look for commits that contain any of the given tags.
            E.g. setting '--tags=foo,bar' will match commits containing
            '[foo,John]', '[bar][foobar]', and '[Doo,foo]'.
            Tags are by default matches case-insensitive (cf --no-ignore-case below).
            The default is '--tags=release,bugfix'.

        --pattern=P
            Will only look for commits whose first line matches the
            given pattern P. This will override a given '--tags' option.
            Patterns are by default matches case-insensitive (cf --no-ignore-case below).

        -a, --all
            Same as '--pattern=\".*\"'.

        --no-ignore-case
            Make tag and pattern matchinh case sensitive.

        -h, --h
            Show this help text.
"

for i in "$@"
do
case $i in
    --from=*)
    FROM="${i#*=}"
    shift # past argument=value
    ;;
    --to=*)
    TO="${i#*=}"
    shift # past argument=value
    ;;
    -a|--all)
    PATTERN=".*"
    shift # past argument=value
    ;;
    --tags=*)
    TAGS="${i#*=}"
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
    -h|--help)
    echo "$USAGE"
    exit 0
    ;;
    --no-ignore-case)
    IGNORECASE=''
    shift # past argument=value
    ;;
    *)
    echo Unknown option passed.
    echo The \'release-cherry-pick.sh --help\' for usage directions.
    exit 1
            # unknown option
    ;;
esac
done

if test -z "$PATTERN"; then
    PATTERN="\[.*`echo $TAGS | sed 's/,/\.\*\\\\]\\\\|\\\\[\.\*/g'`.*\]"
fi

TMPFILE=/tmp/release-cherry-pick.666.$$
git checkout $TO || exit 1

echo Checking for patches to cherry-pick in range $FROM..$TO

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
    REVS=`git rev-list --grep="$PATTERN" $IGNORECASE --cherry-pick --pretty=oneline --reverse --left-only --no-merges $FROM...$TO |grep -v $PREVENTED`
else 
    REVS=`git rev-list --grep="$PATTERN" $IGNORECASE --cherry-pick --pretty=oneline --reverse --left-only --no-merges $FROM...$TO`
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
		    git rev-list --grep="$PATTERN" $IGNORECASE --cherry-pick --reverse --left-only --no-merges $FROM...$TO | grep -v $PREVENTED | xargs git cherry-pick -x -s
		else
		    git rev-list --grep="$PATTERN" $IGNORECASE --cherry-pick --reverse --left-only --no-merges $FROM...$TO | xargs git cherry-pick -x -s
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
