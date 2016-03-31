var express = require('express');
var app = express();

// options copied from express.js guide
var options = {
  dotfiles: 'ignore',
  etag: false,
  extensions: ['htm', 'html'],
  index: false,
  maxAge: '1d',
  redirect: false,
  setHeaders: function (res, path, stat) {
    res.set('x-timestamp', Date.now());
  }
}

app.use(express.static(__dirname));

app.listen(1337, function() {
    console.log('Example app listening on port 1337!');
    console.log(__dirname);
});
