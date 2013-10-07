package RplusMgmt::Controller::Export::Present;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;

use Mojo::Util qw(trim);
use JSON;
use File::Temp qw(tmpnam);
use RTF::Writer;

sub auth {
    my $self = shift;

    return 1;
}

sub index {
    my $self = shift;

    return $self->render_not_found unless $self->req->method eq 'POST';

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'present', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    my $meta = decode_json($media->metadata);

    my $offer_type_code = $self->param('offer_type_code');
    my $add_description_words = $self->param('add_description_words');
    my $phones = trim(scalar $self->param('phones'));

    $meta->{'params'}->{'offer_type_code'} = $offer_type_code;
    $meta->{'params'}->{'add_description_words'} = $add_description_words;
    $meta->{'params'}->{'phones'} = $phones;

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my $file = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    {
        my $rtf = RTF::Writer->new_to_file($file);
        $rtf->prolog('charset' => 'ansicpg1251', colors => [undef, [255,0,0], [0,0,255], [255,255,0]]);

        my @landmarks = sort { ($a->name =~ s/^\((\d+)\).+$/$1/r || '100') <=> ($b->name =~ s/^\((\d+)\).+$/$1/r || 100) } @{Rplus::Model::Landmark::Manager->get_objects(query => [type => 'present', delete_date => undef])};
        push @landmarks, undef;

        my $_format_sum = sub {
            my $sum = shift;

            my ($m, $ths) = (($sum - $sum%1000)/1000, $sum%1000);
            my $human_sum;
            $human_sum = "$m млн." if $m;
            $human_sum .= ($m ? ' ' : '')."$ths тыс." if $ths;

            return $human_sum;
        };

        my $P = $meta->{'params'};

        # Комнаты
        {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        state_code => 'work',
                        offer_type_code => $P->{'offer_type_code'},
                        'type.category_code' => 'room',
                        \("t1.export_media && '{present}'"),
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address_object.expanded_name',
                    with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        if ($l) {
                            $title = "Комнаты. ".($l->name =~ s/^\(\d+\)\s+//r);
                        } else {
                            $title = "Комнаты. Остальное";
                        }
                    }

                    my $location;
                    if ($realty->address_object_id) {
                        my $addrobj = $realty->address_object;
                        $location = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                        if ($realty->sublandmark_id && $location !~ /[()]/) {
                            $location .= ' ('.$realty->sublandmark->name.')';
                        }
                        $location .= '.';
                    }

                    my $type = 'Комн.'.($realty->rooms_count ? ' в '.$realty->rooms_count.'-комн.' : '');

                    my @digest;
                    push @digest, ($P->{'dict'}->{'ap_schemes'}->{$realty->ap_scheme_id} || $realty->ap_scheme->name) if $realty->ap_scheme_id;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, ($realty->floor || '?').'/'.($realty->floors_count || '?') if $realty->floor || $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    if ($P->{'add_description_words'} && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($P->{'add_description_words'} - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $P->{'phones'} || '';
                    if ($phones =~ /%agent\.phone_num%/ && $realty->agent_id) {
                        my $x = decode_json($realty->agent->metadata)->{'public_phone_num'} || $realty->agent->phone_num;
                        $phones =~ s/%agent\.phone_num%/$x/;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        # Малосемейки
        {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        state_code => 'work',
                        offer_type_code => $P->{'offer_type_code'},
                        type_code => 'apartment_small',
                        \("t1.export_media && '{present}'"),
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address_object.expanded_name',
                    with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        if ($l) {
                            $title = "Малосемейки. ".($l->name =~ s/^\(\d+\)\s+//r);
                        } else {
                            $title = "Малосемейки. Остальное";
                        }
                    }

                    my $location;
                    if ($realty->address_object_id) {
                        my $addrobj = $realty->address_object;
                        $location = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                        if ($realty->sublandmark_id && $location !~ /[()]/) {
                            $location .= ' ('.$realty->sublandmark->name.')';
                        }
                        $location .= '.';
                    }

                    my $type = 'Малосем.';

                    my @digest;
                    push @digest, ($P->{'dict'}->{'ap_schemes'}->{$realty->ap_scheme_id} || $realty->ap_scheme->name) if $realty->ap_scheme_id;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, ($realty->floor || '?').'/'.($realty->floors_count || '?') if $realty->floor || $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    if ($P->{'add_description_words'} && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($P->{'add_description_words'} - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $P->{'phones'} || '';
                    if ($phones =~ /%agent\.phone_num%/ && $realty->agent_id) {
                        my $x = decode_json($realty->agent->metadata)->{'public_phone_num'} || $realty->agent->phone_num;
                        $phones =~ s/%agent\.phone_num%/$x/;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        # Квартиры (кроме малосемеек)
        for my $xrc ((1..4), undef) {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        state_code => 'work',
                        offer_type_code => $P->{'offer_type_code'},
                        'type.category_code' => 'apartment',
                        '!type_code' => 'apartment_small',
                        ($xrc ? (rooms_count => $xrc) : (rooms_count => {gt => 4})),
                        \("t1.export_media && '{present}'"),
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address_object.expanded_name',
                    with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        if ($l) {
                            $title = ($xrc ? "${xrc}-комнатные" : 'Многокомнатные').". ".($l->name =~ s/^\(\d+\)\s+//r);
                        } else {
                            $title = ($xrc ? "${xrc}-комнатные" : 'Многокомнатные').". Остальное";
                        }
                    }

                    my $location;
                    if ($realty->address_object_id) {
                        my $addrobj = $realty->address_object;
                        $location = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                        if ($realty->sublandmark_id && $location !~ /[()]/) {
                            $location .= ' ('.$realty->sublandmark->name.')';
                        }
                        $location .= '.';
                    }

                    my $type = ($realty->rooms_count || '?')."-комн.";

                    my @digest;
                    push @digest, ($P->{'dict'}->{'ap_schemes'}->{$realty->ap_scheme_id} || $realty->ap_scheme->name) if $realty->ap_scheme_id;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, ($realty->floor || '?').'/'.($realty->floors_count || '?') if $realty->floor || $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    if ($P->{'add_description_words'} && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($P->{'add_description_words'} - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $P->{'phones'} || '';
                    if ($phones =~ /%agent\.phone_num%/ && $realty->agent_id) {
                        my $x = decode_json($realty->agent->metadata)->{'public_phone_num'} || $realty->agent->phone_num;
                        $phones =~ s/%agent\.phone_num%/$x/;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        # Дома
        {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        state_code => 'work',
                        offer_type_code => $P->{'offer_type_code'},
                        'type.category_code' => 'house',
                        \("t1.export_media && '{present}'"),
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address_object.expanded_name',
                    with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        if ($l) {
                            $title = "Дома. ".($l->name =~ s/^\(\d+\)\s+//r);
                        } else {
                            $title = "Дома. Остальное";
                        }
                    }

                    my $location;
                    if ($realty->address_object_id) {
                        my $addrobj = $realty->address_object;
                        $location = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                        if ($realty->sublandmark_id && $location !~ /[()]/) {
                            $location .= ' ('.$realty->sublandmark->name.')';
                        }
                        $location .= '.';
                    }

                    my $type = $realty->type->name;

                    my @digest;
                    push @digest, $realty->rooms_count.'-комн.' if $realty->rooms_count;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, $realty->floors_count.' эт.' if $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    push @digest, $realty->square_land.' '.(($realty->square_land_type || 'ar') eq 'hectare' ? 'га.' : 'сот.') if $realty->square_land;
                    if ($P->{'add_description_words'} && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($P->{'add_description_words'} - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $P->{'phones'} || '';
                    if ($phones =~ /%agent\.phone_num%/ && $realty->agent_id) {
                        my $x = decode_json($realty->agent->metadata)->{'public_phone_num'} || $realty->agent->phone_num;
                        $phones =~ s/%agent\.phone_num%/$x/;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        $rtf->close;
    }

    $self->res->headers->content_disposition('attachment; filename=present.rtf;');
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;
