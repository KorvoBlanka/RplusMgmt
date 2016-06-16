<meta charset="utf-8">
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.min.js"></script>
<script src="jquery.webSpeech-1.0.1.js?<?=time()?>"></script>
<link rel="stylesheet" type="text/css" href="jquery.webSpeech-1.0.1.css?<?=time()?>">
<title>Web Speech API Demo</title>
<script type="text/javascript">
  $(document).ready(function() {
    $('#test').webSpeech({ format : 'textarea' });
    $('#search').webSpeech({ 
      button : 'webSpeech_search_button', 
      startImg : 'sm-mic.png',
      animateImg : 'sm-mic-on.png',
      errorImg : 'sm-mic-off.png',
      build : 'overwrite', 
      showHelp : false,
      showInterim : false
    });
    $('#div-obj').webSpeech({ button : 'webSpeech_div_button', format : 'html' });
  });
</script>
<h2>Textarea</h2>
<p style="font-style: italic;">Format set for textarea.</p>
<textarea id="test" style="width: 300px; height: 100px;"></textarea>
<button id="webSpeech_button"></button>
<p>&nbsp;</p>
<p>&nbsp;</p>
<p>&nbsp;</p>
<h2>Text Input</h2>
<p style="font-style: italic;">Different images, overwrites, no helper text, no interim text.</p>
<style>
  #webSpeech_search_button {
    background: none;
    border: none;
  }
</style>
<div style="position: relative; width: 200px;">
  <input id="search" type="text" style="width: 200px; height: 24px;">
  <button id="webSpeech_search_button" style="position: absolute; z-index: 10; top: 0; right: 0;"></button>
</div>
<p>&nbsp;</p>
<p>&nbsp;</p>
<p>&nbsp;</p>
<h2>Div</h2>
<p style="font-style: italic;">Format set for HTML.</p>
<div id="div-obj" style="width: 300px; height: 100px; border: solid 1px #000;">&nbsp;</div>
<button id="webSpeech_div_button"></button>
