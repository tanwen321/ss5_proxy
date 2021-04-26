# ss5_proxy
socket proxy server by erlang


##安装

git clone https://github.com/tanwen321/ss5_proxy.git

##编译使用 rebar

rebar3 compile


## 启动

erl -pa _build/default/lib/ss5_proxy/ebin/

Erlang/OTP 23 [erts-11.0] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [hipe]

Eshell V11.0  (abort with ^G)

1> application:start(ss5_proxy).


##配置src/ss5_proxy.app.src 文件

修改

  {env,[{tcp_port, 9527},       %%socket5 server端口
  
  {user, "test"},               %%用户名，如果删除该项是不需要验证
  
  {pass, "test"}]}              %%密码
 
 
