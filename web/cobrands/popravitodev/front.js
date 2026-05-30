(function(){
    if (!document.querySelector) { return; } // Ako nije podržan document.querySelector, prekini izvršavanje
    if (navigator.userAgent.indexOf('Google Page Speed') !== -1) { return; } // Ako se koristi Google Page Speed, prekini izvršavanje
    if (document.cookie.indexOf('has_seen_country_message') !== -1) { return; } // Ako je već postavljena cookie varijabla 'has_seen_country_message', prekini izvršavanje

    // Funkcija za prikazivanje bannera za zemlju
	function showCountryBanner2(banner) {
        banner.children[0].innerHTML = 'Show banner';
        banner.children[1].innerHTML = '';
        banner.children[0].onclick = function(e) {
			showCountryBanner1(banner)
        }
    }
	
	function showCountryBanner1(banner) {
        banner.children[0].innerHTML = 'Hide banner';
        banner.children[1].innerHTML = 'This site is for reporting <strong>problems in Croatia</strong>. The original <a href="https://www.fixmystreet.com/">site</a> is <strong>in the UK</strong>. There are FixMyStreet sites <a href="https://fixmystreet.org/sites/">all over the world</a>, or you could set up your own using the <a href="https://fixmystreet.org/">FixMyStreet Platform</a>.';
		
        banner.children[0].onclick = function(e) {
			showCountryBanner2(banner)
        }
    }
	
	function buildCountryBanner() {
        var banner = document.createElement('div');
        banner.className = 'top_banner top_banner--country';
        
        var close = document.createElement('a');
        close.className = 'top_banner__close';
        close.innerHTML = 'Hide banner';
        close.href = '#';
        close.onclick = function(e) {
			showCountryBanner2(banner)
			//banner.style.display = 'none'; // Sakrij banner
            //var t = new Date(); 
            //t.setFullYear(t.getFullYear() + 1);
            //document.cookie = 'has_seen_country_message=1; path=/; expires=' + t.toUTCString();
        };

        var p = document.createElement('p');
        p.innerHTML = 'This site is for reporting <strong>problems in Croatia</strong>. The original <a href="https://www.fixmystreet.com/">site</a> is <strong>in the UK</strong>. There are FixMyStreet sites <a href="https://fixmystreet.org/sites/">all over the world</a>, or you could set up your own using the <a href="https://fixmystreet.org/">FixMyStreet Platform</a>.';

        banner.appendChild(close);
        banner.appendChild(p);
        document.body.insertBefore(banner, document.body.firstChild);

        // Prikaži banner
        banner.style.display = 'block';
    }

    // AJAX zahtjev za dobivanje informacija o zemlji
	/* Front page banner for other countries */
    var request = new XMLHttpRequest();
    request.open('GET', 'https://gaze.mysociety.org/gaze-rest?f=get_country_from_ip', true);
    request.onreadystatechange = function() {
        if (this.readyState === 4) {
            if (this.status >= 200 && this.status < 400) {
                var data = this.responseText;
                if ( data && data.trim() === 'HR' ) { // Provjeri je li kod zemlje 'HR'
                    buildCountryBanner();
                }
            }
        }
    };
    request.send();
	request = null;
	
})();
