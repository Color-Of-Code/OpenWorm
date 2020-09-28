FROM ubuntu:16.04

LABEL maintainer="David Lung (lungdm@gmail.com); Padraig Gleeson (p.gleeson@gmail.com)"

ARG INTEL_SDK_VERSION=2017_7.0.0.2511_x64

#COPY ./silent-intel-sdk.cfg /tmp/silent-intel-sdk.cfg


ARG USR=ow
ENV USER=$USR

RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get dist-upgrade -y

RUN mkdir -p /etc/sudoers.d && \
  export uid=1000 gid=1000 && \
  mkdir -p /home/$USER && \
  echo "$USER:x:${uid}:${gid}:$USER,,,:/home/$USER:/bin/bash" >> /etc/passwd && \
  echo "$USER:x:${uid}:" >> /etc/group && \
  echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER && \
  chmod 0440 /etc/sudoers.d/$USER && \
  chown ${uid}:${gid} -R /home/$USER


ENV DEBIAN_FRONTEND noninteractive # TODO: change


#RUN useradd -ms /bin/bash $USER


################################################################################
########     Update/install essential libraries

RUN apt-get update && apt-get install -y --no-install-recommends apt-utils \
  wget nano htop build-essential make git automake autoconf \
  g++ rpm libtool libncurses5-dev zlib1g-dev bison flex lsb-core \
  sudo xorg openbox x11-xserver-utils \
  libxext-dev libncurses-dev python-dev mercurial \
  freeglut3-dev libglu1-mesa-dev libglew-dev python-dev python-pip python-lxml python-numpy python-scipy python-tk \
  kmod dkms linux-source linux-headers-generic \
  maven openjdk-8-jdk \
  python-setuptools python-yaml libnuma1 \
  openmpi-bin libopenmpi-dev \
  libgl1-mesa-glx libgl1-mesa-dri libfreetype6-dev \ 
  libpng12-dev libxft-dev python-matplotlib unzip ffmpeg xvfb tmux

#RUN  sudo pip install --upgrade pip
#RUN sudo apt-get install nvidia-opencl-dev

RUN sudo usermod -a -G video $USER

USER $USER
ENV HOME /home/$USER
WORKDIR $HOME

################################################################################
########     Install NEURON simulator

RUN mkdir neuron && \
  cd neuron && \
  git clone https://github.com/nrnhines/iv.git && \
  git clone https://github.com/nrnhines/nrn.git && \
  cd iv && \
  git checkout 76c123b && \
  ./build.sh && \
  ./configure --prefix=`pwd` && \
  make -j3 && \
  sudo make install && \
  cd ../nrn && \
  git checkout e0950a1 && \
  ./build.sh && \
  ./configure --prefix=`pwd` --with-iv=$HOME/neuron/iv --with-nrnpython=/usr/bin/python --with-paranrn && \
  make -j3 && \
  sudo make install && \
  cd src/nrnpython && \
  sudo python setup.py install

  
################################################################################
########     Install pyNeuroML for handling NeuroML network model

RUN pip install cachetools==0.8.0
RUN git clone https://github.com/NeuroML/pyNeuroML.git && \
  cd pyNeuroML && \
  git checkout master  && \
  sudo python setup.py install


################################################################################
########     Install PyOpenWorm

RUN pip install pyparsing==2.0.3 Jinja2==2.11.1 configparser==4.0.2 GitPython==3.0.7 gitdb2==2.0.6 numpydoc==0.9.2 Sphinx==1.8.3 future==0.18.2 setuptools==41.5.1
RUN git clone https://github.com/openworm/PyOpenWorm.git && \
  cd PyOpenWorm && \
  git checkout ow-0.9 && \
  sudo apt-get install -y python-cffi && \
  sudo python setup.py install && \
  pow clone https://github.com/openworm/OpenWormData.git


################################################################################
########     Install c302 for building neuronal network models

RUN git clone https://github.com/openworm/c302.git && \  
  cd c302 && \
  git checkout ow-0.9.1 && \
  sudo python setup.py install


################################################################################
########     Install Sibernetic for the worm body model

RUN git clone https://github.com/openworm/sibernetic.git && \
  cd sibernetic && \
  git checkout ow-0.9.1 # fixed to a specific branch

RUN cp c302/pyopenworm.conf sibernetic/   # Temp step until PyOpenWorm can be run from any dir...


################################################################################
########     Set some paths//environment variables

ENV JNML_HOME=$HOME/jNeuroML
ENV PATH=$PATH:$JNML_HOME
ENV IV=$HOME/neuron/iv
ENV N=$HOME/neuron/nrn
ENV CPU=x86_64
ENV PATH=$PATH:$IV/$CPU/bin:$N/$CPU/bin
ENV NEURON_HOME=$N/$CPU
ENV C302_HOME=$HOME/c302/c302
ENV SIBERNETIC_HOME=$HOME/sibernetic
ENV PYTHONPATH=$PYTHONPATH:$HOME/c302:$SIBERNETIC_HOME

# Not working with --chown=$USER:$USER
COPY ./master_openworm.py $HOME/master_openworm.py
RUN sudo chown $USER:$USER $HOME/master_openworm.py


################################################################################
########     Install Intel OpenCL libraries needed for Sibernetic

RUN mkdir intel-opencl-tmp && \
  cd intel-opencl-tmp && \
  mkdir intel-opencl && \
  wget http://registrationcenter-download.intel.com/akdlm/irc_nas/11396/SRB5.0_linux64.zip && \
  unzip SRB5.0_linux64.zip && \
  tar -C intel-opencl -Jxf intel-opencl-r5.0-63503.x86_64.tar.xz && \
  tar -C intel-opencl -Jxf intel-opencl-devel-r5.0-63503.x86_64.tar.xz && \
  tar -C intel-opencl -Jxf intel-opencl-cpu-r5.0-63503.x86_64.tar.xz && \
  sudo cp -R intel-opencl/* / && \
  sudo ldconfig && \
  cd .. && \
  sudo rm -r intel-opencl-tmp

RUN sudo cp -R /opt/intel/opencl/include/CL /usr/include/ && \
sudo apt install -y ocl-icd-opencl-dev vim
#sudo ln -s /opt/intel/opencl/libOpenCL.so.1 /usr/lib/libOpenCL.so


################################################################################
########     Build Sibernetic

RUN cd sibernetic && \
make clean && make all

# intel i5, hd 5500, linux 4.15.0-39-generic
# ./Release/Sibernetic -f worm -no_g device=CPU    190ms
# ./Release/Sibernetic -f worm -no_g device=GPU    150ms (initialization takes some time)

# Intel(R) Xeon(R) CPU E5-1650 v4 @ 3.60GHz, linux 4.4.0-139-generic
# ./Release/Sibernetic -f worm -no_g device=CPU    60ms
#
# after installing the nvidia driver used in host:
## wget http://us.download.nvidia.com/tesla/390.30/nvidia-diag-driver-local-repo-ubuntu1604-390.30_1.0-1_amd64.deb
## sudo dpkg -i nvidia-diag-driver-local-repo-ubuntu1604-390.30_1.0-1_amd64.deb
## sudo apt-key add /var/nvidia-diag-driver-local-repo-390.30/7fa2af80.pub
## sudo apt-get update
## sudo apt-get install -y cuda-drivers
# ./Release/Sibernetic -f worm -no_g device=GPU    37ms


RUN echo '\n\nalias cd..="cd .."\nalias h=history\nalias ll="ls -alt"' >> ~/.bashrc

RUN echo "Built the OpenWorm Docker image!"