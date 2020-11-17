FROM node:14.4.0

# Create app directory
WORKDIR /usr/src/app


# Install App Dependencies
COPY package*.json ./
RUN npm install

# Bundle app source
COPY . .

# Expose port 3000
EXPOSE 3000

# Start the app
CMD [ "node", "index.js" ]