apt update -y
apt upgrade -y
sudo apt install -y \
  build-essential \
  cmake \
  git \
  libgl1-mesa-dev \
  libglu1-mesa-dev \
  libglew-dev \
  libx11-dev \
  libxi-dev \
  libxrandr-dev \
  libxinerama-dev \
  libxcursor-dev \
  libpng-dev \
  libtiff-dev \
  libjpeg-dev \
  libyaml-cpp-dev \
  qtbase5-dev \
  qttools5-dev \
  zlib1g-dev \
  libblosc-dev

# Python and related
# sudo apt install python3 python3-dev python3-pip python3-numpy

# Graphics and multimedia libraries
# sudo apt install libopenexr-dev libboost-all-dev libtbb-dev
# sudo apt install libopenimageio-dev libopenvdb-dev

# Additional dependencies
# sudo apt install libalembic-dev libglew-dev libglfw3-dev
(graphics) rudycazabon@MSI:~/projects/graphics$ aptitude search python3.12-dev
p   libpython3.12-dev                                                                                                            - Header files and a static library for Python (v3.12)                                                                                  
p   python3.12-dev                                                                                                               - Header files and a static library for Python (v3.12)                                                                                  
v   python3.12-dev:any                                                                                                           -                                                                                                                                       
(graphics) rudycazabon@MSI:~/projects/graphics$ sudo apt install -y libpython3.12-dev python3.12-dev
