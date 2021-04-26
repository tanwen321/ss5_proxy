# ss5_proxy
socket proxy server by erlang


## 安装

git clone https://github.com/tanwen321/ss5_proxy.git

##编译使用 rebar

rebar3 compile


## 启动

erl -pa _build/default/lib/ss5_proxy/ebin/

Erlang/OTP 23 [erts-11.0] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [hipe]

Eshell V11.0  (abort with ^G)

1> application:start(ss5_proxy).


## 配置src/ss5_proxy.app.src 文件

修改

  {env,[{tcp_port, 9527},       %%socket5 server端口
  
  {user, "test"},               %%用户名，如果删除该项是不需要验证
  
  {pass, "test"}]}              %%密码
 
## 说明

1、目前只支持ipv4，只支持socket的connect命令

2、不支持加密，socket5就是要简单，要加密请使用ssr

3、支持匿名和账号2种方式，不支持定义认证，懒得支持




