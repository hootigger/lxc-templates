#!/bin/bash -x

SHELL_DIR=$(cd "$(dirname "$0")";pwd)
OUT=$SHELL_DIR/.build/debian
mkdir -p $OUT && rm -rf $OUT/* 
PACKAGE="tcpdump net-tools dnsutils htop curl zsh git vim less iputils-ping command-not-found"
DEBIAN_VERSION=12

function process() {
	# 更改默认zsh登录
	sed -i 's/\/bin\/bash/\/bin\/zsh/' $1/etc/passwd
	# oh-my-zsh
	cat <<'EOF' > $1/usr/bin/setup-zsh
#!/bin/sh -x
#sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/plugins/zsh-syntax-highlighting
echo "source ~/.oh-my-zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> $HOME/.zshrc
git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/plugins/zsh-autosuggestions
sed -i 's/plugins=(git)/plugins=(git\nz\nzsh-autosuggestions\nzsh-syntax-highlighting\n)/' $HOME/.zshrc

echo "export LS_OPTIONS='--color=auto'" >> $HOME/.zshrc
echo "alias ls='ls \$LS_OPTIONS'" >> $HOME/.zshrc
echo "alias ll='ls \$LS_OPTIONS -alh'" >> $HOME/.zshrc
echo "source /etc/zsh_command_not_found" >> $HOME/.zshrc
EOF
	chmod +x $1/usr/bin/setup-zsh
	# enable dns
	cp -f /etc/resolv.conf $1/etc/resolv.conf
	# install oh my zsh
	chroot $1 setup-zsh
	
	# ssh root login
	chroot $1 sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
	
	# 更改镜像源
	chroot $1 sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
	chroot $1 sed -i 's|security.debian.org/debian-security|mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list
	# debian version
	DEBIAN_VERSION=$(chroot $1 cat /etc/debian_version)
	# 清理dns文件 & zsh
	rm -rf $1/etc/resolv.conf && rm -rf $1/usr/bin/setup-zsh
}


$SHELL_DIR/templates/lxc-debian --name debian --path $OUT --packages "$PACKAGE" $@

if [[ !  $? -eq 0 ]]; then
	echo "错误!"
	exit -1
else
	process $OUT/rootfs
	cd $SHELL_DIR/.build && tar -zcf debian-${DEBIAN_VERSION:-12.2}-custom-base.tar.gz -C $OUT/rootfs . 
fi

