#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use Data::Dumper;

use FindBin;
use lib "$FindBin::Bin/../../lib";

use Rplus::Modern;

use Rplus::Model::AddressObject;
use Rplus::Model::AddressObject::Manager;
use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::MediaImportHistory;
use Rplus::Model::MediaImportHistory::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Rplus::Util::PhoneNum;
use Rplus::Util::Realty;

use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use Time::HiRes;
use File::Path qw(make_path);
use Image::Magick;

use LWP::UserAgent;
use Text::Trim;
use JSON;
use POSIX qw(strftime);

use Mojo::UserAgent;

$| = 1;

my $avito_url = 'http://www.avito.ru';
my $sell_flats_url = 'http://www.avito.ru/habarovsk/kvartiry/prodam';
my $rent_flats_url = 'http://www.avito.ru/habarovsk/kvartiry/sdam';

my $sell_rooms_url = 'http://www.avito.ru/habarovsk/komnaty/prodam';
my $rent_rooms_url = 'http://www.avito.ru/habarovsk/komnaty/sdam';

my $sell_houses_url = 'http://www.avito.ru/habarovsk/doma_dachi_kottedzhi/prodam';
my $rent_houses_url = 'http://www.avito.ru/habarovsk/doma_dachi_kottedzhi/sdam';

my $sell_land_url = 'http://www.avito.ru/habarovsk/zemelnye_uchastki/prodam';

my $img_path = '/mnt/data/storage/raven';
my $media_num = '0_0';

my $ua_name = '"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_3) AppleWebKit/534.54.16 (KHTML, like Gecko) Version/5.1.4 Safari/534.54.16"';

my $pause = 20 * 60;

my $MEDIA = Rplus::Model::Media::Manager->get_objects(query => [type => 'import', code => 'avito', delete_date => undef])->[0];	# code => 'avito'
exit unless $MEDIA;
my $META = decode_json($MEDIA->metadata);

my $ua = Mojo::UserAgent->new;
$ua->max_redirects(3);
$ua->transactor->name($ua_name);

my $proxy_ua = Mojo::UserAgent->new;
$proxy_ua->proxy->http("http://212.19.22.218:8080");
$proxy_ua->connect_timeout(15);
$proxy_ua->inactivity_timeout(30);
$proxy_ua->max_redirects(8);
$proxy_ua->transactor->name($ua_name);

# Загрузим базу телефонов посредников
my %MEDIATOR_PHONES;
{
	my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(query => [delete_date => undef], require_objects => ['company']);
	while (my $x = $mediator_iter->next) {
		$MEDIATOR_PHONES{$x->phone_num} = {
			id => $x->id,
			name => $x->name,
			company => $x->company->name,
		};
	}
}

import_avito ();

sub import_avito {
	my @url_list;

	# sell flats -------------------------------------------------------------
	@url_list = load_url_list($sell_flats_url, 2);
	say "--------------------- " . (scalar @url_list) . " url in flats sell list ---------------------";
	process_url_list(\@url_list, 'apartment', 'sale');
	
	sleep $pause;
	
	# rent flats -------------------------------------------------------------
	@url_list = load_url_list($rent_flats_url, 2);
	say "--------------------- " . (scalar @url_list) . " url in flats rent list ---------------------";
	process_url_list(\@url_list, 'apartment', 'rent');

	sleep $pause;
	
	# sell rooms -------------------------------------------------------------
	@url_list = load_url_list($sell_rooms_url, 2);
	say "--------------------- " . (scalar @url_list) . " url in rooms sell list ---------------------";
	process_url_list(\@url_list, 'room', 'sale');
	
	sleep $pause;	
	
	# rent rooms -------------------------------------------------------------
	@url_list = load_url_list($rent_rooms_url, 2);
	say "--------------------- " . (scalar @url_list) . " url in rooms rent list ---------------------";
	process_url_list(\@url_list, 'room', 'rent');
		
	sleep $pause;		
		
	# sell houses -------------------------------------------------------------
	@url_list = load_url_list($sell_houses_url, 2);
	say "--------------------- " . (scalar @url_list) . " url in houses sell list ---------------------";
	process_url_list(\@url_list, 'house', 'sale');

	sleep $pause;
	
	# rent houses -------------------------------------------------------------
	@url_list = load_url_list($rent_houses_url, 2);
	say "--------------------- " . (scalar @url_list) . " url in houses rent list ---------------------";
	process_url_list(\@url_list, 'house', 'rent');
	
	sleep $pause;	
	
	# sell land -------------------------------------------------------------
	@url_list = load_url_list($sell_land_url, 2);
	say "--------------------- " . (scalar @url_list) . " url in land sell list ---------------------";
	process_url_list(\@url_list, 'land', 'sale');
}

sub load_url_list{
	my @url_list;
	my ($main_page, $page_count) = @_;
	
	for(my $i = 1; $i < $page_count; $i ++) {
		sleep 10;
		my $dom = $ua->get($main_page.'?p='.$i)->res->dom;
		$dom->find('div[class^="item"]')->each (
		sub{
			my $do = $_->find('div[class="data"]');
			if($do->size && trim $do->first->all_text ne 'Агентство') {
				$do = $_->find('div[class="description"]');
				if ($do->size) {
					push(@url_list, $do->first->h3->a->{href});
				}
			}
		});
	}
	return @url_list;
}

sub process_url_list {
	my ($url_list_ref, $category_code, $offer_type) = @_;
	
	for my $item_url (@$url_list_ref){
	
		say 'processing ' . $item_url;
		my $data = {
			source_media_id => $MEDIA->id,
		};
		
		$data->{'category_code'} = $category_code;
		$data->{'type_code'} = $category_code;
		$data->{'offer_type_code'} = $offer_type;
		
		eval {
			# берем данные с основного сайта
			sleep 25;
			my $dom = $ua->get($avito_url . $item_url)->res->dom;
			# описание
			my $dsk = $dom->find('div[itemprop="description"]')->first->all_text;
			# Пропустим уже обработанные объявления
			if (Rplus::Model::MediaImportHistory::Manager->get_objects_count(query => [media_id => $MEDIA->id, media_num => $media_num, media_text => $dsk])) {
				say 'was processed already';
				next;
			}
			$data->{'source_media_text'} = $dsk;
			
			# берем телефон со страницы "мобильного" сайта
			my $m_avito = "http://m.avito.ru" . $item_url . '/phone';
			sleep 25;
			my $do = $proxy_ua->get($m_avito)->res->dom->find('a[class^="button-text"]');
			if ($do->size > 0) {				
				my $phone_str = $do->first->text;
				$phone_str =~ s/\D//g;
				if (length $phone_str > 5) {
					if (my $phone_num = Rplus::Util::PhoneNum->parse($phone_str, $META->{'params'}->{'default_phone_prefix'})) {
						$data->{'owner_phones'} = $phone_num;
					}
				}
			}
			
			# Пропустим объявления без номеров телефонов
			if(not defined  $data->{'owner_phones'}) {
				say "no phone was found";
				next;
			}
			# Пропустим объявления посредников
			if(exists $MEDIATOR_PHONES{$data->{'owner_phones'}}) {
				say "Found mediator, phone: $data->{'owner_phones'}";
				next;
			}
		
			# заголовок осн. информация
			my $main_title = $dom->find('h1[class^="item_title"]')->first->all_text;
			$main_title = trim $main_title;
			given($data->{'type_code'}) {
				when ('room') {
					my @bp = grep { $_ && length($_) > 1 } trim(split /[,()]/, $main_title);
					# комната м2 бла...
					if ($bp[0] =~ /^.*?(\d{1,}).*?$/) {
						$data->{'square_total'} = $1;
					}					
					# d/d эт.
					if (defined $bp[1] && $bp[1] =~ /^(\d{1,2})\/(\d{1,2}).*?$/) {
						if ($2 >= $1) {
							$data->{'floor'} = $1;
							$data->{'floors_count'} = $2;
						}
					}
				}
				when ('apartment') {
					my @bp = grep { $_ && length($_) > 1 } trim(split /[,()]/, $main_title);
					# d-к квратира.
					if ($bp[0] =~ /^(\d{1,}).*?$/) {
						$data->{'rooms_count'} = $1;
					}
					# d м2.
					if ($bp[1] =~ /^(\d{1,}).*?$/) {
						$data->{'square_total'} = $1;
					}
					# d/d эт.
					if ($bp[2] =~ /^(\d{1,2})\/(\d{1,2}).*?$/) {
						if ($2 >= $1) {
							$data->{'floor'} = $1;
							$data->{'floors_count'} = $2;
						}
					}					
				}
				when ('house') {
					given($main_title) {
						when (/дом/i) {
						}
						when (/коттедж/i) {
							$data->{'type_code'} = 'cottage';
						}
						# дача
						default {next;}
					}
					
					# d м2 d сот || d м2
					if ($main_title !~ /участке/) {
						if ($main_title =~ /^.*?(\d{1,}).*?$/) {
							$data->{'square_total'} = $1;
						}
					} elsif ($main_title =~ /^.*?(\d{1,}).*?(\d{1,}).*?$/) {
						$data->{'square_total'} = $1;
						$data->{'square_land'} = $2;
						$data->{'square_land_type'} = 'ar';
					}					
				}
				when ('land') {
					if ($main_title =~ /(\d+(?:,\d+)?)\s+кв\.\s*м/) {
						$main_title =~ s/\s//;
						if ($main_title =~ /^(\d{1,}).*?$/) {
							$data->{'square_land'} = $1;
						}	
					} elsif ($main_title =~ s/(\d+)\s+сот\.?//) {
						$data->{'square_land'} = $1;
						$data->{'square_land_type'} = 'ar';
					} elsif ($main_title =~ s/(\d(?:,\d+)?)\s+га//) {
						$data->{'square_land'} = $1 =~ s/,/./r;
						$data->{'square_land_type'} = 'hectare';
					}
				}
				default {}
			}

			# Разделим остальную часть обявления на части и попытаемся вычленить полезную информацию
			my @bp = grep { $_ && length($_) > 1 } trim(split /[,()]/, $data->{'source_media_text'});
			for my $el (@bp) {
			    # Этаж/этажность
			    if ($el =~ /^(\d{1,2})\/(\d{1,2})$/) {
					if ($2 > $1) {
						$data->{'floor'} = $1;
						$data->{'floors_count'} = $2;
					}
					next;
			    }
		
			    for my $k (keys %{$META->{'params'}->{'dict'}}) {
					my %dict = %{$META->{'params'}->{'dict'}->{$k}};
					my $field = delete $dict{'__field__'};
					for my $re (keys %dict) {
						if ($el =~ /$re/i) {
							$data->{$field} = $dict{$re};
							last;
						}
					}
			    }
			}
			
			# цена в рублях, переведем в тыс.
			my $price = $dom->find('strong[itemprop="price"]')->first->all_text;
			$price =~s/\s//g;
			if ($price =~ /^(\d{1,}).*?$/) {
				$data->{'owner_price'} = $1 / 1000;
			}
		
			# адр
			if ($data->{'type_code'} eq 'room' || $data->{'type_code'} eq 'apartment') {
			my $addr = $dom->find('span[itemprop="streetAddress"]')->first->all_text;
			# Распознавание адреса
			if ($addr) {				
				# уберем "районы", "остановки" и остальной мусор
				my @sadr = split(/,/, $addr);
				my @t;
				for my $ap (@sadr) {
					if($ap !~ /^.*?р-н.*?/ && $ap !~ /^ост.*?/ && $ap !~ /^[г|Г]\..*?/) {
						$ap =~ s/\(.*?\)//g;
						$ap =~ s/[д|Д]ом//g;
						$ap =~ s/[д|Д]\.//g;
						push(@t, $ap);
					}
				}
				$addr = join(', ', @t);
				my $ts_query = join(' | ', grep { $_ && length($_) > 1 } split(/\W/, $addr));
				if ($ts_query) {
					$ts_query =~ s/'/''/g;
					    my $addrobj = Rplus::Model::AddressObject::Manager->get_objects(
						query => [
						# english - чтобы не отбрасывались окончания
						    \("t1.fts @@ to_tsquery('russian', '$ts_query')"),
						    parent_guid => $META->{'params'}->{'ao_parent_guid'},
						    curr_status => 0,
						    level => 7,
						],
					    sort_by => "ts_rank(t1.fts2, to_tsquery('russian', '$ts_query')) desc, case when short_type = 'ул' then 0 else 1 end",
					    limit => 1,
					)->[0];
					if ($addrobj) {
						if ($addr =~ /,\s+(\d+(?:\w)?)/) {
						    $data->{'house_num'} = uc($1);
						    # Запросим координаты объекта
						    my %coords = get_coords_by_addr($addrobj, uc($1));
						    if (%coords) {
							# say "Fetched coords: ".$coords{'latitude'}.", ".$coords{'longitude'};
							@{$data}{keys %coords} = values %coords;
						    }
						}
						$data->{'address_object_id'} = $addrobj->id;
					}
				}
			}
			}

			my $id;
			if ($id = Rplus::Util::Realty->find_similar(%$data, state_code => ['raw', 'work', 'suspended'])) {
				say "Found similar realty: $id";
			} else {
				eval {
					my $realty = Rplus::Model::Realty->new((map { $_ => $data->{$_} } grep { $_ ne 'category_code' } keys %$data), state_code => 'raw');
					$realty->save;
					my $id = $realty->id;
					say "Saved new realty: $id";
					
					# вытащим фото
					$dom->find('div[class*="ll fit"]')->each (
					sub {
						my $img_url = 'http:' . $_->a->{href};	
						say 'loading image '.$img_url;
						my $image = $ua->get($img_url)->res->content->asset;
						load_images($id, $image);
					});
				} or do {
					say $@;
				}
			}
			
			# Сохраним историю
			if ($id && !Rplus::Model::MediaImportHistory::Manager->get_objects_count(query => [media_id => $MEDIA->id, media_num => $media_num, realty_id => $id])) {
				eval {
					Rplus::Model::MediaImportHistory->new(media_id => $MEDIA->id, media_num => $media_num, media_text => $data->{'source_media_text'}, realty_id => $id)->save;
				} or do {};
			}
		}
	}
}

sub load_images {
	my ($realty_id, $file) = @_;
	
	my $path = $img_path.'/photos/'.$realty_id;
	my $name = Time::HiRes::time =~ s/\.//r; # Unique name

	my $photo = Rplus::Model::Photo->new;
	eval {
		make_path($path);
		$file->move_to($path.'/'.$name.'.jpg');

		# Convert image to jpeg
		my $image = Image::Magick->new;
		$image->Read($path.'/'.$name.'.jpg');
		if ($image->Get('width') > 1920 || $image->Get('height') > 1080 || $image->Get('mime') ne 'image/jpeg') {
			$image->Resize(geometry => '1920x1080');
			$image->Write($path.'/'.$name.'.jpg');
		}
		$image->Resize(geometry => '320x240');
		$image->Extent(geometry => '320x240', gravity => 'Center', background => 'white');
		$image->Thumbnail(geometry => '320x240');
		$image->Write($path.'/'.$name.'_thumbnail.jpg');

		# Save
		$photo->realty_id($realty_id);
		$photo->filename($name.'.jpg');
		$photo->thumbnail_filename($name.'_thumbnail.jpg');

		$photo->save;
	} or do {
		say $@;
	};

	# Update realty change_date
	Rplus::Model::Realty::Manager->update_objects(
		set => {change_date => \'now()'},
		where => [id => $realty_id],
	);
}

# вычисление pkey для получения картинки номера телефона
sub calc_pkey {
	my ($id, $photo_id) = @_;
	my $mixed =  $_[1] % 2 == 0 ? reverse $_[0] : $_[0];
	my $s = length($mixed);
	my $r = '';
	my $k;
		
	for($k = 0; $k < $s; $k ++)	{
		if($k % 3 == 0){
			$r = $r . substr($mixed, $k, 1);
		}
	}
		
	return $r;
}

# Геокодирование 2GIS
sub get_coords_by_addr {
    my ($addrobj, $house_num) = @_;

    state $_geocache;

    my ($latitude, $longitude);
    my $q = decode_json($addrobj->metadata)->{'addr_parts'}->[1]->{'name'}.', '.$addrobj->name.', '.$house_num;

    return @{$_geocache->{$q}} if exists $_geocache->{$q};
    if (my $realty = Rplus::Model::Realty::Manager->get_objects(select => ['id', 'latitude', 'longitude'], query => [address_object_id => $addrobj->id, house_num => $house_num, '!latitude' => undef, '!longitude' => undef], limit => 1)->[0]) {
	return latitude => $realty->latitude, longitude => $realty->longitude;
    }

    my $ua = LWP::UserAgent->new;
    my $response = $ua->post(
	'http://catalog.api.2gis.ru/geo/search',
	[
	    q => $q,
	    key => 'rujrdp3400',
	    version => '1.3',
	    output => 'json',
	    types => 'house',
	],
	Referer => 'http://catalog.api.2gis.ru/',
    );
    if ($response->is_success) {
	eval {
	    my $data = decode_json($response->decoded_content);
	    return unless $data->{'total'};
	    if (my $centroid = $data->{'result'}->[0]->{'centroid'}) {
		if ($centroid =~ /^POINT\((\d+\.\d+) (\d+\.\d+)\)$/) {
		    ($longitude, $latitude) = ($1, $2);
		    $_geocache->{$q} = [latitude => $latitude, longitude => $longitude];
		}
	    }
	    1;
	} or do {};
    } else {
	say "2GIS Invalid response (q: $q)";
    }

    return ($latitude && $longitude ? (latitude => $latitude, longitude => $longitude) : ());
}