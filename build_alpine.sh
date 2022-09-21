#!/bin/bash -x

SHELL_DIR=$(cd "$(dirname "$0")";pwd)
OUT=$SHELL_DIR/.build/alpine
mkdir -p $OUT && rm -rf $OUT/* && mkdir -p $OUT/rootfs
PACKAGE="tcpdump net-tools bind-tools htop curl zsh git vim openssh"
VERSION=3.16

function process() {
	# 更改默认zsh登录
	sed -i 's/\/bin\/ash/\/bin\/zsh/' $1/etc/passwd
	# 打开ll
	cat <<'EOF' > $1/etc/profile.d/alias_bash.sh
export LS_OPTIONS='--color=auto'
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -alh'
EOF
	echo "export PS1='\u@\h:\w $ '" > $1/etc/profile.d/ps.sh.disable
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
cat /etc/profile.d/alias_bash.sh >> $HOME/.zshrc
#clear
#zsh
EOF
	chmod +x $1/usr/bin/setup-zsh
	# enable dns
	cp -f /etc/resolv.conf $1/etc/resolv.conf
	# install oh my zsh
	chroot $1 setup-zsh

	# ssh root login
        chroot $1 sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

	# auto start sshd
	chroot $1 rc-update add sshd 

	# os version
	VERSION=$(chroot $1 cat /etc/alpine-release)


	# 清理dns文件 & zsh
	rm -rf $1/etc/resolv.conf && rm -rf $1/usr/bin/setup-zsh
}


$SHELL_DIR/templates/lxc-alpine --name alpine --path $OUT $PACKAGE $@

if [[ !  $? -eq 0 ]]; then
	echo "错误!"
	exit -1
else
	process $OUT/rootfs
	cd $SHELL_DIR/.build && tar -zcf alpine-${VERSION:-3.16}-custom-base.tar.gz -C $OUT/rootfs . 
fi

