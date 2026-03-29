#!/bin/bash -x

SHELL_DIR=$(cd "$(dirname "$0")";pwd)
OUT=$SHELL_DIR/.build/debian
mkdir -p $OUT && rm -rf $OUT/* 
PACKAGE="tcpdump net-tools dnsutils htop curl zsh git vim less iputils-ping command-not-found"
DEBIAN_RELEASE=bookworm

function fallback_debian_version() {
	case "$1" in
		bookworm) echo 12 ;;
		bullseye) echo 11 ;;
		buster) echo 10 ;;
		stretch) echo 9 ;;
		jessie) echo 8 ;;
		wheezy) echo 7 ;;
		testing|unstable|sid) echo "$1" ;;
		*) echo "$1" ;;
	esac
}

ARCHIVE_DEBIAN_VERSION=$(fallback_debian_version "$DEBIAN_RELEASE")

function process() {
	# 更改默认zsh登录
	sed -i 's/\/bin\/bash/\/bin\/zsh/' $1/etc/passwd
	# oh-my-zsh
	cat <<'EOF' > $1/usr/bin/setup-zsh
#!/bin/sh -ex
#sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh || exit 1
cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/plugins/zsh-syntax-highlighting || exit 1
echo "source ~/.oh-my-zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> $HOME/.zshrc
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/plugins/zsh-autosuggestions || exit 1
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
	chroot $1 setup-zsh || { echo "setup-zsh 失败!"; exit 1; }
	
	# ssh root login
	chroot $1 sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
	
	# 更改镜像源 (兼容传统 sources.list 与 Debian 12+ DEB822 格式)
	if [ -f "$1/etc/apt/sources.list" ]; then
		sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' $1/etc/apt/sources.list
		sed -i 's|security.debian.org/debian-security|mirrors.ustc.edu.cn/debian-security|g' $1/etc/apt/sources.list
	fi
	if [ -f "$1/etc/apt/sources.list.d/debian.sources" ]; then
		sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' $1/etc/apt/sources.list.d/debian.sources
		sed -i 's|security.debian.org/debian-security|mirrors.ustc.edu.cn/debian-security|g' $1/etc/apt/sources.list.d/debian.sources
	fi
	# debian version
	DETECTED_DEBIAN_VERSION=$(chroot "$1" cat /etc/debian_version 2>/dev/null) && ARCHIVE_DEBIAN_VERSION=$DETECTED_DEBIAN_VERSION
	# 清理dns文件 & zsh
	rm -rf $1/etc/resolv.conf && rm -rf $1/usr/bin/setup-zsh
}


$SHELL_DIR/templates/lxc-debian --name debian --release "$DEBIAN_RELEASE" --path "$OUT" --packages "$PACKAGE" "$@"

if [[ !  $? -eq 0 ]]; then
	echo "错误!"
	exit -1
else
	process "$OUT/rootfs"
	cd "$SHELL_DIR/.build" && tar -zcf "debian-${ARCHIVE_DEBIAN_VERSION}-custom-base.tar.gz" -C "$OUT/rootfs" . 
fi
