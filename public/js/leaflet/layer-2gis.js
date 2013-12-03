(function () {
  "use strict";

  if (!window.Rplus) { window.Rplus = {}; }
  if (!window.Rplus.GeoMap) { window.Rplus.GeoMap = {}; }

  window.Rplus.GeoMap.initLayer = function (map) {
    if (!map) return;

    var layer = L.tileLayer('http://tile{s}.maps.2gis.com/tiles?x={x}&y={y}&z={z}&v=10', {
      maxZoom: 18,
      subdomains: '0123',
      errorTileUrl: 'http://maps.api.2gis.ru/images/nomap.png',
      attribution: '<a href="http://http://2gis.ru/">2GIS</a> Layer | RplusMgmt',
    });
    layer.addTo(map);

    // 2GIS Geocoder
    map.on('click', function (e) {
      $.ajax({
        url: 'http://catalog.api.2gis.ru/geo/search',
        data: {
          q: e.latlng.lng + ',' + e.latlng.lat,
          key: 'rujrdp3400',
          version: 1.3,
          output: 'jsonp',
          types: 'house,station,station_platform,place,sight,metro'
        },
        dataType: 'jsonp',
      })
        .done(function (data) {
          if (data.result) {
            var content = '';
            content += '<b>Info:</b><br>';
            content += data.result[0].name + '<br>';
            if (data.result[0].attributes && data.result[0].attributes.purpose) {
              content += data.result[0].attributes.purpose;
            }
            var popup = L.popup()
                         .setLatLng(e.latlng)
                         .setContent(content)
                         .openOn(map);
          }
        })
      ;
    });
  }
})();
