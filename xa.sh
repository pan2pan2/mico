mico_path="${root}/root/mico.sh"
mico_initpath="${root}/etc/init.d/mico_enable"
# 部署脚本
echo "部署启动脚本"
echo "#!/bin/sh /etc/rc.common
START=96
start() {
  sh '${mico_path}' &
}
stop() {
  kill \`ps|grep 'sh ${mico_path}'|grep -v grep|awk '{print \$1}'\`
}" > $mico_initpath
chmod a+x $mico_initpath > /dev/null 2>&1
$mico_initpath enable > /dev/null 2>&1
$mico_initpath stop > /dev/null 2>&1

echo "安装完毕"
echo "可以使用/etc/init.d/mico_enable start 启动小爱拦截器"
