# This script is responsible for deploying the public facing eOffer
# User Guides website.
#
# This script accepts a file path that references a directory that
# contains the source code for the eOffer User Guides website. It
# archives the directory, uploads the directory to an Amazon Web
# Services (AWS) Simple Storage Service (S3) bucket, and sends a
# notification email to the GSA IT Tech support team.

path=""
bucket=""
email=""
cc=""

# Accepts one argument: message, a message
# string; and prints the given message iff the
# verbose flag has been set.
function notice () {
  local msg=$1

  if [[ $verbose == 1 ]]
  then
    echo -e "\033[44mNotice:\033[0m $msg"
  fi
}

# Accepts one argument: message, a message
# string; and prints the given message iff the
# verbose flag has been set.
function error () {
  local emsg=$1

  echo -e "\033[41mError:\033[0m $emsg"
  exit 1
}

options=$(getopt --options="hvp:b:e:c:" --longoptions="help,verbose,version,path:,bucket:,email:,cc:" -- "$@")
[ $? == 0 ] || error "Invalid command line. The command line includes one or more invalid command line parameters."

eval set -- "$options"
while true
do
  case "$1" in
    -h | --help)
      cat <<- EOF
Usage: ./eoffer_deply_script.sh [options] <required arguments>

This script deploys eOffer User Guides website packages. The script
accepts a local file path that references a directory containing
the eOffer User Guides source files. It copies and archives the
directory and uploads the archive to an AWS S3 bucket. Once uploaded,
it sends a notification email to the GSA tech support team.

Options:

  -h|--help
  Displays this message.

  -v|--verbose
  Enables verbose output.

  --version
  Displays the current version of this program.

Required Options:

  -p|--path <path>
  Gives a file path that references the source code directory.

  -b|--bucket <bucket>
  Gives the ID of the S3 bucket that this script will upload the
  package to.

  -e|--email <email address>
  Gives the email address that the notification email will be sent to

  -c|--cc <email addresses>
  Gives a space delimited list of emails that will be carbon copied
  on the notification email.
EOF
      exit 0;;
    -v|--verbose)
      verbose=1
      shift;;
    --version)
      echo "version: 1.0.0"
      exit 0;;
    -p|--path)
      path=$2
      shift 2;;
    -b|--bucket)
      bucket=$2
      shift 2;;
    -e|--email)
      email=$2
      shift 2;;
    -c|--cc)
      cc=$2
      shift 2;;
    --)
      shift
      break;;
  esac
done
shift $((OPTIND - 1))

echo $bucket

[[ -z $path ]]   && error "Invalid command line. The <path> argument is missing."
[[ -z $bucket ]] && error "Invalid command line. The <bucket> argument is missing."
[[ -z $email ]]  && error "Invalid command line. The <email> argument is missing."

# Accepts one argument, $cmd, a bash command
# string, executes the command and returns an
# error message if it fails.
function execute () {
  local cmd=$1
  echo $cmd
  eval $cmd
  [ $? == 0 ] || error "An error occured while trying to execute the following command: "'"'$cmd'"'"."
}

bucket="s3://$bucket"
datestamp=$(date +%m%d%y)
source="$(basename $path)-$datestamp"
package="$source.tar.bz2"
hash="$source.sha1"

# I. Create the source directory.

notice "Creating the source directory..."
execute "cp -rf $path $source"
execute "rm -rf $source/{.git,.sass-cache}"
execute "rm -f $source/{.gitattributes,.gitignore,config.rb}"
notice "Created the source directory."

# II. Package the source directory.

notice "Creating the deployment package..."
tar --bzip2 -cvf $package $source
sha1sum $package > $hash
notice "Created the deployment package."

exit 0

# III. Post the package to AWS.

notice "Posting the deployment package to AWS..."
aws s3 cp $package $bucket --acl public-read-write
aws s3 cp $hash $bucket --acl public-read-write
notice "Posted the deployment package to AWS."

# IV. Send notification email.

read -a carboncopy <<< $cc

cc=""
for recipient in "${carboncopy[@]}"
do
  cc="-c $recipient $cc"
done

echo $cc

carboncopy="-c [[Robert Sherwood|Robert]].Sherwood@nolijconsulting.com -c thomas.ahn@gsa.gov -c larry.lee@nolijconsulting.com"

display "Notifying GSA..."
mutt -s "Please deploy the Vendor Facing Release Notes Package" $cc $email <<- EOF
Hi,
The latest version of the Vendor Facing Release Notes (https://eoffer-test.fas.gsa.gov/AMSupport/vendor-release-notes/) is ready for deployment.
The source code package for this project can be downloaded from:
* https://s3.amazonaws.com/amsystemssupport.fas.gsa.gov/$package
* https://s3.amazonaws.com/amsystemssupport.fas.gsa.gov/$hash
The source code package for this site consist entirely of HTML, JS, CSS, and XML files. To deploy this package, simply replace the existing source files with those included in the package.
Please let me know once this update has been installed.
Thanks,
-- 
Larry Lee
EOF
display "Notification email sent."
