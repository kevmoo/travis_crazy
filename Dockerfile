FROM node
RUN git clone https://github.com/kevmoo/travis_crazy.git
WORKDIR travis_crazy
RUN ./monkey.sh
