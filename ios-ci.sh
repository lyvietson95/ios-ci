# created by TungNQ

version="1.0.1"

# the resource path
resource_path="$(brew --cellar ios-ci)/$version"

if [ "$1" == "__test_cmd" ] || [ "$1" == "--version" ]; then
    echo $version
    exit 1
fi

# ========== INIT ==========
deploy_path="$(pwd)/.ci"
export_config_name="export_config.plist"
deploy_config_name="deploy_config.json"

if [ "$1" == "init" ]; then
    # get resource
    if [ ! -d "${resource_path}" ]; then
        echo "=> Resource not found, please 'brew upgrade ios-ci'"
        exit 1
    fi

    deploy_path="./.ci"
    if [ -d "${deploy_path}" ] && [ "$2" != "-f" ]; then
        echo "=> This project is initialized, please 'ios-ci init -f' to re-init"
        exit 1
    fi

    # Create deploy path...
    rm -rf ${deploy_path}
    mkdir ${deploy_path}

    # ... deploy_config & export_config files
    cp -R ${resource_path}/config/${export_config_name} ${deploy_path}/${export_config_name}
    cp -R ${resource_path}/config/${deploy_config_name} ${deploy_path}/${deploy_config_name}

    # ... hooks dir and files inside
    mkdir ${deploy_path}/hooks
    cp -R ${resource_path}/hooks/ ${deploy_path}/hooks/
    
    exit 1
fi

# check this project is initialized?
deploy_config_path="${deploy_path}/${deploy_config_name}"

if [ ! -e "${deploy_config_path}" ]; then
    echo "=> ${deploy_config_name} not found at ${deploy_path}"
    echo "=> Need initialize first: ios-ci init [-f]"
    exit 1
fi

# check input argument
is_archive=0
is_export=0
if [ "$1" == "-a" ]; then
    is_archive=1
    echo "ARCHIVE"
elif [ "$1" == "-e" ]; then
    is_export=1
    echo "EXPORT"
else
    echo "=> Argument not found, ex: ios-ci -a, ..."
    exit 1
fi

cmd_path="${deploy_path}/hooks"

# parse json func
value=""
get_value()
{
    value=$(jq ".$1" ${deploy_config_path} | tr -d \")
}

# get the .xcodeproj path
get_value project_path
project_path=${value}

# get archive_scheme name
get_value archive_scheme
archive_scheme=${value}

# get the archive path
get_value archive_path
archive_path=${value}
archive_file_path="${archive_path}/${archive_scheme}.xcarchive"

# create dir if needed
if [ ! -d "${archive_path}" ]; then
    mkdir ${archive_path}
fi

# ========== ARCHIVE ==========
# prepare vars for archiving steps
project_full_name=$(find ${project_path} -iname '*.xcodeproj')
project_name=$(basename ${project_full_name} ".xcodeproj")
project_path="${project_path}/${project_name}.xcodeproj"

# Run Pre Archive job
sh ${cmd_path}/pre_archive.sh ${deploy_config_path} ${archive_path}

# Run Archive job
echo "=> Archiving... ${archive_scheme}.xcarchive"
xcodebuild -project ${project_path} -scheme ${archive_scheme} -configuration Release archive -archivePath ${archive_file_path}

if [ ! -e "${archive_file_path}" ]; then
    rm -rf ${archive_path}
    exit 1
fi

# Run Post Archive job
sh ${cmd_path}/post_archive.sh ${deploy_config_path} ${archive_path} ${archive_scheme}.xcarchive

if [ $is_archive == 1 ]; then
    exit 1
fi

# ========== EXPORT ==========
# path to ${export_config_name}
export_config_path="${deploy_path}/${export_config_name}"
if [ ! -e "${export_config_path}" ]; then
    echo "=> ${export_config_name} not found at ${deploy_path}"
    echo "=> Need initialize first: ios-ci init [-f]"
    exit 1
fi

# prepare vars for exporting steps
file_exported_name="${archive_scheme}.ipa"

# create export path
export_id=$(uuidgen)
export_path="${archive_path}/Export_${export_id}"
mkdir ${export_path}

# Run Pre Export job
sh ${cmd_path}/pre_export.sh ${deploy_config_path} ${export_path}

# Run Export job
echo "=> Exporting... ${file_exported_name}"
xcodebuild -exportArchive -archivePath ${archive_file_path} -exportOptionsPlist ${export_config_path} -exportPath ${export_path}

if [ ! -e "${export_path}/${file_exported_name}" ]; then
    exit 1
fi

# Run Post Export job
sh ${cmd_path}/post_export.sh ${deploy_config_path} ${export_path} ${file_exported_name}