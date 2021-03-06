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
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use Spreadsheet::WriteExcel;
use JSON;

my $config;

sub index {
    my $self = shift;

    $config = $self->config;

    my $acc_id = $self->session('account')->{id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'farpost', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    my $meta = from_json($media->metadata);

    my @sale_realty_types = split ',', $self->param('sale_realty_types');
    my @rent_realty_types = split ',', $self->param('rent_realty_types');

    my %query_apartments;
    my %query_houses;
    $query_apartments{sale} = [grep { $_ =~ /apartment|apartment_small|room/ } @sale_realty_types];
    $query_apartments{rent} = [grep { $_ =~ /apartment|apartment_small|room/ } @rent_realty_types];
    $query_houses{sale} = [grep { $_ !~ /apartment|apartment_small|room/ } @sale_realty_types];
    $query_houses{rent} = [grep { $_ !~ /apartment|apartment_small|room/ } @rent_realty_types];


    my $conf_phones = '';
    my $agent_phone = 0;

    my $meta = from_json($media->metadata);

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $conf_phones = $e_opt->{'farpost-phones'} ? trim($e_opt->{'farpost-phones'}) : '';
        $agent_phone = 1 if $e_opt->{'present-agent-phone'};
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
            my $header_fmt2 = $workbook->add_format();
            $header_fmt2->copy($header_fmt1);
            my $header = {
                'A1' => { text => "Тип сделки", width => 15 },
                'B1' => { text => "Кол. комн." },
                'C1' => { text => "Р-он", width => 22 },
                'D1' => { text => "Улица", width => 35 },
                'E1' => { text => "Номер дома" },
                'F1' => { text => "Общая площадь, кв.м." },
                'G1' => { text => "Этаж" },
                'H1' => { text => "Всего этажей" },
                'I1' => { text => "Адрес расположения проектной декларации" },
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

            my $row_num = 1;
            foreach (keys %query_apartments) {
                my $offer_type_code = $_;
                my $types = $query_apartments{$offer_type_code};
                next unless scalar @$types;

                my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        offer_type_code => $offer_type_code,
                        type_code => $types,
                        export_media => {'&&' => $media->id},
                        account_id => $acc_id,
                    ],
                    sort_by => 'address',
                    require_objects => ['type', 'offer_type'],
                    with_objects => ['sublandmark', 'condition', 'agent'],
                );
                while(my $realty = $realty_iter->next) {
                    my $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'farpost', delete_date => undef], limit => 1)->[0] if @{$realty->landmarks};
                    my $phones = $conf_phones;
                    if ($agent_phone == 1 && $realty->agent) {
                        my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $realty->id, delete_date => undef])};

                    my $rooms_count = '';
                    if ($realty->type_code eq 'apartment') {
                        $rooms_count = $realty->rooms_count;
                    } else {
                        $rooms_count = $realty->type->name;
                    }

                    my $row = [
                        $realty->offer_type->name,
                        $rooms_count || '',
                        $area ? $area->name : '',
                        $realty->address && $realty->locality ? $addr = $r->locality .', '. $r->address;,
                        $realty->house_num || '',
                        $realty->square_total || '',
                        $realty->floor || '',
                        $realty->floors_count || '',
                        'нет',
                        $realty->description,
                        @photos ? {type => 'photo_list', body => join("\n", map { $config->{storage}->{external} . '/photos/' . $_->filename } @photos)} : '',
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
        }

        $workbook->close;
    }

    $self->res->headers->content_disposition('attachment; filename=farpost.xls;');
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;
