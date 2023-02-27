#!/bin/bash
lux=/usr/local/bin/lux

function init()
{
    #telegram参数
    telegram_bot_token=""
    telegram_chat_id=""
    #RSS 地址
    rssURL="https://rsshub.app/bilibili/$1/$2/$3 -q -O -"
    #脚本存放地址
    scriptLocation="/root/bilidown/bili-cookies/"
    #视频存放地址
    videoLocation="/root/bilidown/bili-down/$4/"
    #远程目录地址
    remote=""

    #如果时间戳记录文本不存在则创建（此处文件地址自行修改）
    if [ ! -f "${scriptLocation}data.txt" ]; then
        touch "$scriptLocation"data.txt
        echo "2023-01-01 00:00:00" >"$scriptLocation"data.txt
    fi
    specified_date=$(tail -1 "${scriptLocation}data.txt"|awk -F, '{print $1}')
    echo $specified_date
}




function check()
{
    stat=$($lux -i -c "$scriptLocation"cookies.txt https://www.bilibili.com/video/BV1fK4y1t7hj)
    substat=${stat#*Quality:}
    data=${substat%%#*}
    quality=${data%%Size*}
    if [[ $quality =~ "1080P" ]]; then
        echo "checked"
        return 1;
    else
        curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id=$telegram_chat_id -d parse_mode=html -d text="<b>BFD：Cookies 文件失效，请更新后重试</b>%0A%0A$videomessage"
    fi
}


function download()
{
    #清空 Bilibili 文件夹
    rm -rf "$videoLocation"*
    if [[ ! -d "$videoLocation$name" ]];then
        mkdir -p $videoLocation$name
    fi

    stat=$($lux -i -p -c "$scriptLocation"cookies.txt $link)
    if [  $? -ne 0 ];then
        message=$(echo $name 获取视频信息失败，跳过...)
        echo $message
        curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id=$telegram_chat_id -d parse    _mode=html -d text="<b>BFD：获取状态信息失败</b>%0A%0A$message"
        return 3
    fi
    #echo $stat
    #有几P视频 ,注意这里分隔符会根据全局变量分割
    count=$(echo $stat | awk -F'Title' '{print NF-1}')
    echo $count
    # 查询分p信息，只下载链接对应分p
    for ((i = 0; i < $count; i++)); do
        stat=${stat#*Title:}
        title=${stat%%Type:*}
        substat=${stat#*Quality:}
        data=${substat%%#*}
        quality=${data%%Size*}
        size=${data#*Size:}
        title=$(echo $title)
        quality=$(echo $quality)
        size=$(echo $size)
        #每一P的视频标题，清晰度，大小，发邮件用于检查下载是否正确进行
        #message=${message}"Title: "${title}$'\n'"Quality: "${quality}$'\n'"Size: "${size}$'\n\n' #邮件方式
        message=${message}"Title:%20"${title}"%0AQuality:%20"${quality}"%0ASize:%20"${size}"%0A%0A" #telegram方式
    done
    # 开始下载通知
    curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id=$telegram_chat_id -d parse_mode=html -d text="<b>BFD：开始下载</b>%0A%0A$message"
    message=""

    #下载封面图（图片存储位置应和视频一致）
    wget -P "$videoLocation$name" $photolink

    #下载视频
    count=1
    cur_sec=`date '+%s'`
    echo "1" > "${scriptLocation}${cur_sec}mark.txt"
    while true; do
        $lux  -eto -C  -c "$scriptLocation"cookies.txt -o "$videoLocation$name" $link > "${scriptLocation}${cur_sec}.txt"
        if  [ $? -eq 0 ]; then
            #下载完成
            echo "0" > "${scriptLocation}${cur_sec}mark.txt"

            #重命名封面图
            pname=${photolink#*archive/}
            result1=$(echo $pname | grep "jpg")
            if [ "$result1" != "" ]; then
                mv "$videoLocation$name"/$pname "$videoLocation$name"/poster.jpg
            else
                mv "$videoLocation$name"/$pname "$videoLocation$name"/poster.png
            fi

            #xml转ass && 获取下载完的视频文件信息
            for file in "$videoLocation$name"/*; do
                if [ "${file##*.}" = "xml" ]; then
                    "${scriptLocation}"DanmakuFactory -o "${file%%.cmt.xml*}".ass -i "$file"
                    #删除源文件
                    #rm "$file"
                elif [ "${file##*.}" = "mp4" ] || [ "${file##*.}" = "flv" ] || [ "${file##*.}" = "mkv" ]; then
                    videoname=${file#*"$name"\/}
                    videostat=$(du -h "$file")
                    videosize=${videostat%%\/*}
                    videosize=$(echo $videosize)
                    #videomessage=${videomessage}"Title: "${videoname}$'\n'"Size: "${videosize}$'\n\n'  #邮件方式
                    videomessage=${videomessage}"Title:%20"${videoname}"%0ASize:%20"${videosize}"%0A%0A" #telegram方式
                fi
            done
            videomessage=""
            curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id=$telegram_chat_id -d parse_mode=html -d text="<b>BFD：下载完成</b>%0A%0A$videomessage"
            echo "开始上传"
            # 处理文件名有引号的情况
            if [[ $title =~ '"' ]];then
                echo "find $videoLocation$name -depth -name "*\"*" -execdir sh -c 'mv "$1" "${1//\"/-}"' sh {} \;"
                find $videoLocation$name -depth -name "*\"*" -execdir sh -c 'mv "$1" "${1//\"/-}"' sh {} \;
            fi
            /usr/bin/rclone copy "$videoLocation" "$remote" 2>"$PWD/temp.txt"
            if [ $? -eq 0 ];then

                curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id=$telegram_chat_id -d parse_mode=html -d text="<b>BFD：上传完成</b>%0A%0A$title"
                echo "${info_comma[@]:0:3}"
                echo "${info_comma[@]:0:3}" >>"$scriptLocation"data.txt
            else
                echo "上传失败"
                message=$(cat "$PWD/temp.txt")
                curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id=$telegram_chat_id -d parse_mode=html -d text="<b>BFD：上传失败</b>%0A%0A$message"
            fi
            break
        # 下载命令没有成功执行
        else
            if [ "$count" != "1" ];then
                count=$(($count + 1))
                sleep 2
            else
                rm -rf "$videoLocation$name"
                curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id=$telegram_chat_id -d parse_mode=html -d text="<b>BFD：下载失败</b>"
                exit
            fi
        fi
    message=""
    done &

    second="start"
    secondResult=$(curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -d chat_id=$telegram_chat_id -d parse_mode=html -d text="$second")
    subSecondResult="${secondResult#*message_id\":}"
    messageID=${subSecondResult%%,\"from*}
    count=0
    while true; do
        sleep 2
        text=$(tail -1 "${scriptLocation}${cur_sec}.txt")
        echo $text > "${scriptLocation}${cur_sec}${cur_sec}.txt"
        sed -i -e 's/\r/\n/g' "${scriptLocation}${cur_sec}${cur_sec}.txt"
        text=$(sed -n '$p' "${scriptLocation}${cur_sec}${cur_sec}.txt")
        result=$(curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/editMessageText" -d chat_id=$telegram_chat_id -d message_id=$messageID -d text="$text")
        mark=$(cat "${scriptLocation}${cur_sec}mark.txt")
        if [ $mark -eq 0 ]; then
            break
        fi
    done
    wait
    rm "${scriptLocation}${cur_sec}.txt"
    rm "${scriptLocation}${cur_sec}${cur_sec}.txt"
    rm "${scriptLocation}${cur_sec}mark.txt"
}

# getContent
#找到所有大于更新日期的item
#取item中的信息
#记录title author link pubdate到data.txt
#data.txt 按cst时间正序排列
#check download getInfo

function getInfo()
{
    rsscontent=$(wget $rssURL -q -O -)
    echo $rssURL
    specified_timestamp=$(date -d "$specified_date" +%s) # 转换成时间戳


    # 提取信息的正则表达式
    title_regex="<title><!\[CDATA\[(.*)\]\]></title>"
    author_regex="<author><!\[CDATA\[(.*)\]\]></author>"
    link_regex="<link>(.*)<\/link>"


    res=$(echo $rsscontent|sed -n '/<item>/,/<\/item>/p'  | sed ':a;N;$!ba;s/\n/ /g' |grep -o -P "<item>.*?</item>"|while read -r item; do
    pubDate=$(echo "$item" | grep -o -E "<pubDate>.*</pubDate>" | sed -e "s/<[^>]*>//g") # 提取pubDate
    timestamp=$(date -d "$pubDate" +%s) # 转换成时间戳
    if [ "$timestamp" -gt "$specified_timestamp" ]; then # 如果pubDate在指定日期之后
        # 提取信息
        if [[ $item =~ $title_regex ]]; then
            title="${BASH_REMATCH[1]}"
        fi
        if [[ $item =~ $author_regex ]]; then
            author="${BASH_REMATCH[1]}"
        fi
        if [[ $item =~ $link_regex ]]; then
            link="${BASH_REMATCH[1]}"
        fi
        #获得封面图下载链接
        subcontent=${item#*<img src=\"}
        photolink=${subcontent%%\"*}
        echo  "$(date -d "$pubDate" +"%Y-%m-%d %H:%M:%S"),$title,$author,$link,$photolink"
    fi
    done |sort -t , -k 1n )
}
# 初始化全局参数
init $1 $2 $3 $4

# 获取rss中待下载视频信息
getInfo

# 以换行符分割
IFS=$'\n'
# 分割为数组
rssdata=($res)
echo ${#rssdata[@]}
check
if [ $? -eq 1 ];then
    for i in ${rssdata[@]}; do
        info_comma=($i)
        IFS=$','
        info=($i)

        # 改分割字符，不然分割分p信息时会出错
        IFS=$'\n'
        #数组下标从0开始
        name=${info[1]}
        link=${info[3]}
        photolink=${info[4]}
        echo "$name $link"
        download $link $name $photolink
    done
fi
