FROM node
RUN apt-get update
RUN apt-get install unzip
RUN git clone https://github.com/kevmoo/travis_crazy.git
WORKDIR travis_crazy
RUN pwd
RUN git ls-remote --get-url origin
RUN ./monkey.sh
