const express = require('express')
var bodyParser = require('body-parser')
const exec = require('child_process').exec

const app = express()
const port = 3000

var jsonParser = bodyParser.json()

app.post('/', jsonParser, (req, res) => {
  exec('bash scripts/plex-update-cache.sh', (error, stdout, stderr) => {
    if (error) {
      console.error(`exec error: ${error}`);
      res.status(500);
      res.send();
      return;
    }
    console.log(`stdout: ${stdout}`);
    console.error(`stderr: ${stderr}`);
    res.send('OK');
  });
})

app.listen(port, () => {
  console.log(`Plex Hook listening at http://localhost:${port}`)
})



