# Lua 5.1
wget -O - http://www.lua.org/ftp/lua-5.1.5.tar.gz | tar xz
cd lua-5.1.5;
make linux test
cd ..;
export PATH=$PATH:/home/travis/build/OXGaming/oxscripts/lua-5.1.5/bin