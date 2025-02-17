# @author FlashSoft
# == 自定义配置========================================
# 设定拦截词,以竖线分割每个拦截词,被拦截的内容会转发给nodered服务器进行处理
keywords=""
# 配置nodered的接收地址
nodered_url="http://192.168.2.20:1880/"
# 配置从nodered更新拦截词的间隔,单位秒
# 0代表不更新,一直使用本地拦截词
# 大于0则更新,会从上面设定的nodered_url去获取拦截词,并覆盖本地的拦截词
keywords_update_timeout=5
# == /自定义配置========================================
 
asr_file="/tmp/mipns/mibrain/mibrain_asr.log"
res_file="/tmp/mipns/mibrain/mibrain_txt_RESULT_NLP.log"
nodered_auth="admin:admin"
 
# 解决可能存在第一次文件不存在问题
touch $res_file && touch $asr_file
res_md5=""
last_time=`date +%s`
 
echo "== 拦截词: $keywords"
echo "== NodeRed地址:$nodered_url"
echo "== 更新拦截词时间间隔 $keywords_update_timeout 秒"
 
while true;do
  # 计算md5值 
  new_md5=`md5sum $res_file | awk '{print $1}'`
  # 如果是第一次,就赋值比较用的md5
  [ -z $res_md5 ] && res_md5=$new_md5
  # 如果md5不等则文件变化
  if [[ $new_md5 != $res_md5 ]];then
    # 记录md5变化后结果
    res_md5=$new_md5
 
    
    # 获取asr内容
    asr_content=`cat $asr_file`
    # 获取res内容
    res_content=`cat $res_file`
 
    # echo $asr_content
    # echo ""
    # echo $res_content

    # 如果拦截词不为空,且匹配到了拦截词则试图拦截

    # if [ "`echo "$res_content"|grep '"domain": "smartMiot"'`" ];then
    miai_domain=`echo "$res_content"|awk -F '"domain":' '{print $2}'|awk -F '"' '{print $2}'`
    miai_errcode=`echo "$res_content"|awk -F '\"extend\":' '{print $2}'|awk -F '\"code\":' '{print $2}'|awk -F ',' '($1>200){print $1}'`
    echo "== 有内容更新 | type: $miai_domain errcode: $miai_errcode"
    
    if ([[ ! -z $keywords ]] && [[  ! -z `echo "$res_content"|awk 'match($0,/'$keywords'/){print 1}'` ]]) || [ $miai_errcode ];then
      echo "== 试图停止"
      # 若干循环,直到resume成功一次直接跳出
      seq 1 200 | while read line;do
        code=`ubus call mediaplayer player_play_operation {\"action\":\"resume\"}|awk -F 'code":' '{print $2}'`
        if [[ "$code" -eq "0" ]];then
          echo "== 停止成功"
          break
        fi
        usleep 50
      done
 
      # 记录播放状态并暂停,方便在HA服务器处理逻辑的时候不会插播音乐,0为未播放,1为播放中,2为暂停
      play_status=`ubus -t 1 call mediaplayer player_get_play_status | awk -F 'status' '{print $2}' | cut -c 5`
      # echo $play_status
      ubus call mediaplayer player_play_operation {\"action\":\"pause\"} > /dev/null 2>&1
 
      # @todo:
      # 转发asr和res给服务端接口,远端可以处理控制逻辑完成后返回需要播报的TTS文本
      # 2秒连接超时,4秒传输超时
      tts=`curl --insecure -u "$nodered_auth" –connect-timeout 2 -m 4 -s --data-urlencode "asr=$asr_content" --data-urlencode "res=$res_content" $nodered_url`
      echo "== 请求完成"

      # 如果远端返回内容不为空则用TTS播报之
      if [[ -n "$tts" ]];then
        echo "== 播报TTS | TTS内容: $tts"
        ubus call mibrain text_to_speech "{\"text\":\"$tts\",\"save\":0}" > /dev/null 2>&1
        # 最长20秒TTS播报时间,20秒内如果播报完成跳出
        seq 1 20 | while read line;do
          media_type=`ubus -t 1 call mediaplayer player_get_play_status|awk -F 'media_type' '{print $2}'|cut -c 5`
          if [ "$media_type" -ne "1" ];then
            echo "== 播报TTS结束"
            break
          fi
          sleep 1
        done
      fi
 
      # 如果之前音乐是播放的则接着播放
      if [[ "$play_status" -eq "1" ]];then
        echo "== 继续播放音乐"
        # 这里延迟一秒是因为前面处理如果太快,可能引起恢复播放不成功
        sleep 1
        ubus call mediaplayer player_play_operation {\"action\":\"play\"} > /dev/null 2>&1
      fi
    fi
  fi
 
  # 以某频度去更新拦截词
  if [[ "$keywords_update_timeout" -gt "0" ]];then
    now=`date +%s`
    step=`expr $now - $last_time`
    # 根据设定时间间隔获取更新词
    if [[ "$step" -gt "$keywords_update_timeout" ]];then
        keywords=`curl --insecure -u "$nodered_auth" –connect-timeout 2 -m 4 -s $nodered_url`
        echo "== 更新关键词 | 关键词内容: $keywords"
        last_time=`date +%s`
    fi
  fi
  usleep 10
done
