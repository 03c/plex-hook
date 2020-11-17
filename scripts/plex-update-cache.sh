#!/bin/bash

HtmlToTextOut=""
HtmlToText () {
    HtmlToTextOut=$1
    HtmlToTextOut="${HtmlToTextOut//&nbsp;/ }"
    HtmlToTextOut="${HtmlToTextOut//&amp;/&}"
    HtmlToTextOut="${HtmlToTextOut//&lt;/<}"
    HtmlToTextOut="${HtmlToTextOut//&gt;/>}"
    HtmlToTextOut="${HtmlToTextOut//&quot;/'"'}"
    HtmlToTextOut="${HtmlToTextOut//&#39;/"'"}"
    HtmlToTextOut="${HtmlToTextOut//&ldquo;/'"'}"
    HtmlToTextOut="${HtmlToTextOut//&rdquo;/'"'}"
    HtmlToTextOut="${HtmlToTextOut//&#8217;/''}"
}

declare -A mappings
video_paths=()

plex_host=http://192.168.1.10:32400
plex_token=yyspehp2Fk_gurwZTmNk

mappings["tv"]="mnt/user/Television"
mappings["movies"]="mnt/user/Films"

IFS=$'\n'
files=($(curl -s $plex_host/library/onDeck?X-Plex-Token=$plex_token | grep -oP 'file="\K/[^"]+'))

for i in ${!files[@]}
do
  file=${files[$i]/tv/${mappings[tv]}}
  file=${file/movies/${mappings[movies]}}
  HtmlToText $file
  video_paths+=($HtmlToTextOut)
done

video_min_size="100MB" # 2GB, to exclude bonus content
preload_head_size="60MB" # 60MB, raise this value if your video buffers after ~5 seconds
preload_tail_size="1MB" # 1MB, should be sufficient even for 4K
video_ext='avi|mkv|mov|mp4|mpeg' # https://support.plex.tv/articles/203824396-what-media-formats-are-supported/
sub_ext='srt|smi|ssa|ass|vtt' # https://support.plex.tv/articles/200471133-adding-local-subtitles-to-your-media/#toc-1
free_ram_usage_percent=80
preclean_cache=0
notification=1
# #####################################
# 
# ######### Script ####################
# make script race condition safe
if [[ -d "/tmp/${0///}" ]] || ! mkdir "/tmp/${0///}"; then exit 1; fi; trap 'rmdir "/tmp/${0///}"' EXIT;
# check user settings
video_min_size="${video_min_size//[!0-9.]/}" # float filtering https://stackoverflow.com/a/19724571/318765
video_min_size=$(awk "BEGIN { print $video_min_size*1000000}") # convert MB to Bytes
preload_head_size="${preload_head_size//[!0-9.]/}"
preload_head_size=$(awk "BEGIN { print $preload_head_size*1000000}")
preload_tail_size="${preload_tail_size//[!0-9.]/}"
preload_tail_size=$(awk "BEGIN { print $preload_tail_size*1000000}")
# clean the read cache
if [ "$preclean_cache" = "1" ]; then
    sync; echo 1 > /proc/sys/vm/drop_caches
fi
# preload
preloaded=0
skipped=0
preload_total_size=$(($preload_head_size + $preload_tail_size))
free_ram=$(free -b | awk '/^Mem:/{print $7}')
free_ram=$(($free_ram / 100 * $free_ram_usage_percent))
echo "Available RAM in Bytes: $free_ram"
preload_amount=$(($free_ram / $preload_total_size))
echo "Amount of Videos that can be preloaded: $preload_amount"
# fetch video files
while IFS= read -r -d '' file; do
    if [[ $preload_amount -le 0 ]]; then
        break;
    fi
    size=$(stat -c%s "$file")
    if [ "$size" -gt "$video_min_size" ]; then
        TIMEFORMAT=%R
        benchmark=$(time ( head -c $preload_head_size "$file" ) 2>&1 1>/dev/null )
        echo "Preload $file (${benchmark}s)"
        if awk 'BEGIN {exit !('$benchmark' >= '0.200')}'; then
            preloaded=$((preloaded + 1))
        else
            skipped=$((skipped + 1))
        fi
        tail -c $preload_tail_size "$file" > /dev/null
        preload_amount=$(($preload_amount - 1))
        video_path=$(dirname "$file")
        # fetch subtitle files
        find "$video_path" -regextype posix-extended -regex ".*\.($sub_ext)" -print0 | 
            while IFS= read -r -d '' file; do 
                echo "Preload $file"
                cat "$file" >/dev/null
            done
    fi
done < <(find "${video_paths[@]}" -regextype posix-extended -regex ".*\.($video_ext)" -printf "%T@ %p\n" | sort -nr | cut -f2- -d" " | tr '\n' '\0')
# notification
if [[ $preloaded -eq 0 ]] && [[ $skipped -eq 0 ]]; then
    /usr/local/emhttp/webGui/scripts/notify -i alert -s "Plex Preloader failed!" -d "No video file has been preloaded (wrong path?)!"
elif [ "$notification" = "1" ]; then
    /usr/local/emhttp/webGui/scripts/notify -i normal -s "Plex Preloader has finished" -d "$preloaded preloaded (from Disk) / $skipped skipped (already in RAM)"
fi