#!/bin/bash

[[ "${DEBUG_MODE}" == "true" ]] && ffmpeglog="debug" || ffmpeglog="error"
echo $ffmpeglog
current_file_dir=$(dirname "$0")

# Start nginx server
/usr/local/nginx/sbin/nginx -c /root/app/nginx.conf

# Check if the folder exist
cd /root/picam/archive/ || exit 1
mkdir -p \
  /root/picam/archive/lapse/output \
  /root/picam/archive/lapse/recycle \
  /root/picam/archive/lapse/images

# Stop converting on Ctrl-C
trap on_sigint INT
on_sigint() {
  echo "Stop converting"
  exit 0
}

check_disk_usage() {
  while :
  do
    echo "Check disk capacity..."
    used_percentage=$(df --output=pcent / | tr -dc '0-9')
    if [ $used_percentage -gt 93 ]; then
      echo "Disk usage: $used_percentage%, trying to trim files ..."
      latestfile=$(ls -1rt *.mp4 | head -n1)
      rm "$latestfile"
    else
      echo "Pass"
      break
    fi

    echo "Waiting for 10 seconds and check disk usage again..."
    sleep 10
  done
}

get_date_from_filename() {
  echo $1 | cut -d'_' -f 1
}

process_ts_file() {
  local latestfile="$1"
  echo "`date`: Processing $latestfile.ts and "
  echo "Creating lapse video: ./lapse/$latestfile.ts ..."

  local outputs="\
    -acodec copy -vcodec copy ${latestfile}.mp4 \
    -vf setpts=PTS/250 -r 20 -video_track_timescale 10k -vcodec h264_omx -an ./lapse/${latestfile}.mp4"
  if [ "$IMAGE_ON" == "true" ]; then
    local image_date=$(get_date_from_filename "$latestfile")
    mkdir -p "./lapse/images/$image_date"
    outputs="${outputs} -vf fps=1/60 ./lapse/images/$image_date/$latestfile.img%02d.jpg"
  fi
  nice -15 ffmpeg -y -v $ffmpeglog -vcodec h264_mmal -i "$latestfile.ts" ${outputs}

  delete_if_file_empty "./lapse/$latestfile.mp4"
  rm "$latestfile.ts"

  echo "`date`: Done"
}

convert_video_file() {
  if [[ `date "+%H:%M"` > "07:10"  ]]; then
    $current_file_dir/lapse.sh `date -d "-1 day" "+%Y-%m-%d"`
  fi

  local ts_files_number=$(ls -1t ./*.ts | wc -l)
  echo "$ts_files_number ts files left."

  if [ $ts_files_number -gt 1 ]; then
    echo "Start converting..."
    local latestfile=$(ls -1t *.ts | head -n2 | tail -n1 | sed -e 's/\.ts$//')
    process_ts_file "$latestfile"
  fi
}

delete_if_file_empty() {
  _file="$1"
  [ $# -eq 0 ] && { echo "Usage: $0 filename"; exit 1; }
  [ ! -f "$_file" ] && { echo "Error: $0 file not found."; exit 2; }

  if [ ! -s "$_file" ]
  then
    echo "$_file is empty. Removeing it ..."
    rm -f "$_file"
    echo "$_file deleted"
  fi
}

# CONVERT_VIDEO=false
while true; do
  check_disk_usage

  if [ "$CONVERT_VIDEO" == "true" ]; then
    convert_video_file
  else
    echo CONVERT_VIDEO: "$CONVERT_VIDEO" Skip convertting videos ...
  fi

  echo "Waiting for one minutes to see if any more ts file need to be convert..."
  sleep 1m
done
