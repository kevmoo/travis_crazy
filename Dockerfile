FROM node
ADD * ./
RUN chmod +x monkey.sh
RUN ./monkey.sh
