package RplusMgmt::Controller::Export::Farpost;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use Spreadsheet::WriteExcel;
use JSON;

sub index {
    my $self = shift;

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'farpost', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    my $meta = from_json($media->metadata);

    my $offer_type_code = $self->param('offer_type_code');
    my $realty_types = $self->param('realty_types');

    my $conf_phones = '';
    my $agent_phone = 0;

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'export')->load();
    if ($rt_param) {
        my $config = from_json($rt_param->{value});
        $conf_phones = $config->{'farpost-phones'} ? trim($config->{'farpost-phones'}) : '';
        $agent_phone = 1 if $config->{'present-agent-phone'};
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my $file = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    {
        my $workbook = Spreadsheet::WriteExcel->new($file);

        my $P = $meta->{'params'};

        {
            my $worksheet = $workbook->add_worksheet("Квартиры");

            # Заголовок листа
            my $header_fmt1 = $workbook->add_format(border => 1, bold => 0, bg_color => 'silver', valign  => 'vcenter', align => 'center', text_wrap => 1);
            my $header_fmt2 = $workbook->add_format(); $header_fmt2->copy($header_fmt1);
            my $header = {
                'A1' => { text => "Тип сделки", width => 15 },
                'B1' => { text => "Тип недвижимости", width => 15 },
                'C1' => { text => "Кол. комн." },
                'D1' => { text => "Р-он", width => 22 },
                'E1' => { text => "Улица", width => 35 },
                'F1' => { text => "Номер дома" },
                'G1' => { text => "Общая площадь, кв.м." },
                'H1' => { text => "Этаж" },
                'I1' => { text => "Всего этажей" },
                'J1' => { text => "Дополнительное описание", width => 25 },
                'K1' => { text => "Ссылки на фотографии", width => 70 },
                'L1' => { text => "Цена руб." },
            };
            for my $x (keys %$header) {
                if ($x =~ /^(\S)\d$/) {
                    $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt1);
                    $worksheet->set_column("$1:$1", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
                } elsif ($x =~ /^(\S)(\d)\:(\S)(\d)$/) {
                    $worksheet->merge_range($x, $header->{$x}->{'text'}, $header_fmt2);
                    $worksheet->set_column("$1:$3", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
                }
            }

            my $txt_fmt = $workbook->add_format(num_format => '@');
            my $txt_fmt2 = $workbook->add_format(); $txt_fmt2->set_text_wrap();

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => $offer_type_code,
                    or => [
                      type_code => 'apartment',
                      type_code => 'apartment_small',
                      type_code => 'room',
                    ],
                    export_media => {'&&' => $media->id},
                ],
                sort_by => 'address_object.expanded_name',
                require_objects => ['type', 'offer_type'],
                with_objects => ['address_object', 'sublandmark', 'condition', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'farpost', delete_date => undef], limit => 1)->[0] if @{$realty->landmarks};
                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }
                my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $realty->id, delete_date => undef])};

                my $row = [
                    $realty->offer_type->name,
                    $realty->type->name,
                    $realty->rooms_count || '',
                    $area ? $area->name : '',
                    $realty->address_object ? $realty->address_object->name.($realty->address_object->short_type ne 'ул' ? ' '.$realty->address_object->short_type : '') : '',
                    $realty->house_num || '',
                    $realty->square_total || '',
                    $realty->floor || '',
                    $realty->floors_count || '',
                    $realty->description,
                    @photos ? {type => 'photo_list', body => join("\n", map { $self->config->{'storage'}->{'url'}.'/photos/'.$_->realty_id.'/'.$_->filename } @photos)} : '',
                    $realty->price * 1000,
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    my $x = $row->[$col_num];
                    if (ref($x) eq 'HASH') {
                        if ($x->{'type'} eq 'photo_list') {
                            $worksheet->set_row($row_num, 60);
                            $worksheet->write_string($row_num, $col_num, $x->{'body'}, $txt_fmt2);
                        }
                    } else {
                        $worksheet->write($row_num, $col_num, $x);
                    }
                }
                $row_num++;
            }
        }

=begin comment
        {
            my $worksheet = $workbook->add_worksheet("Частные дома и котеджи");

            # Заголовок листа
            my $header_fmt1 = $workbook->add_format(border => 1, bold => 0, bg_color => 'silver', valign  => 'vcenter', align => 'center', text_wrap => 1);
            my $header_fmt2 = $workbook->add_format(); $header_fmt2->copy($header_fmt1);
            my $header = {
                'A1' => { text => "Тип сделки", width => 15 },
                'B1' => { text => "Тип недвижимости", width => 15 },
                'С1' => { text => "Р-он", width => 22 },
                'D1' => { text => "Расположение", width => 35 },
                'E1' => { text => "Тип дома" },
                'F1' => { text => "Площадь участка(сот.)" },
                'G1' => { text => "Площадь.дома,кв.м." },
                'H1' => { text => "Кол.ком." },
                
                'I1' => { text => "Права на участок" },
                'J1' => { text => "Водоснабжение" },
                'K1' => { text => "Электричество" },
                'L1' => { text => "Отопление" },
                
                'M1' => { text => "Дополнительное описание", width => 25 },
                'N1' => { text => "Ссылки на фотографии", width => 70 },
                'O1' => { text => "Цена руб." },
            };
            for my $x (keys %$header) {
                if ($x =~ /^(\S)\d$/) {
                    $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt1);
                    $worksheet->set_column("$1:$1", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
                } elsif ($x =~ /^(\S)(\d)\:(\S)(\d)$/) {
                    $worksheet->merge_range($x, $header->{$x}->{'text'}, $header_fmt2);
                    $worksheet->set_column("$1:$3", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
                }
            }

            my $txt_fmt = $workbook->add_format(num_format => '@');
            my $txt_fmt2 = $workbook->add_format(); $txt_fmt2->set_text_wrap();

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    or => [
                      type_code => 'cottage',
                      type_code => 'house',
                    ]
                    export_media => {'&&' => $media->id},
                ],
                sort_by => 'address_object.expanded_name',
                require_objects => ['type', 'offer_type'],
                with_objects => ['address_object', 'sublandmark', 'condition', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'farpost', delete_date => undef], limit => 1)->[0] if @{$realty->landmarks};
                my $phones = $P->{'phones'} || '';
                if ($phones =~ /%agent\.phone_num%/ && $realty->agent_id) {
                    my $x = from_json($realty->agent->metadata)->{'public_phone_num'} || $realty->agent->phone_num;
                    $phones =~ s/%agent\.phone_num%/$x/;
                }
                my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $realty->id, delete_date => undef])};

                'A1' => { text => "Тип сделки", width => 15 },
                'B1' => { text => "Тип недвижимости", width => 15 },
                'С1' => { text => "Р-он", width => 22 },
                'D1' => { text => "Расположение", width => 35 },
                'E1' => { text => "Тип дома" },
                'F1' => { text => "Площадь участка(сот.)" },
                'G1' => { text => "Площадь.дома,кв.м." },
                'H1' => { text => "Кол.ком." },
                
                'I1' => { text => "Права на участок" },
                'J1' => { text => "Водоснабжение" },
                'K1' => { text => "Электричество" },
                'L1' => { text => "Отопление" },
                
                'M1' => { text => "Дополнительное описание", width => 25 },
                'N1' => { text => "Ссылки на фотографии", width => 70 },
                'O1' => { text => "Цена руб." },
                
                my $row = [
                    $realty->offer_type->name,
                    $realty->type->name,
                    $realty->rooms_count || '',
                    $area ? $area->name : '',
                    $realty->address_object ? $realty->address_object->name.($realty->address_object->short_type ne 'ул' ? ' '.$realty->address_object->short_type : '') : '',
                    $realty->house_num || '',
                    $realty->square_total || '',
                    $realty->floor || '',
                    $realty->floors_count || '',
                    $realty->description,
                    @photos ? {type => 'photo_list', body => join("\n", map { $self->config->{'storage'}->{'url'}.'/photos/'.$_->realty_id.'/'.$_->filename } @photos)} : '',
                    $realty->price * 1000,
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    my $x = $row->[$col_num];
                    if (ref($x) eq 'HASH') {
                        if ($x->{'type'} eq 'photo_list') {
                            $worksheet->set_row($row_num, 60);
                            $worksheet->write_string($row_num, $col_num, $x->{'body'}, $txt_fmt2);
                        }
                    } else {
                        $worksheet->write($row_num, $col_num, $x);
                    }
                }
                $row_num++;
            }
        }        
=end comment
=cut
        
        $workbook->close;
    }

    $self->res->headers->content_disposition('attachment; filename=farpost.xls;');
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;
