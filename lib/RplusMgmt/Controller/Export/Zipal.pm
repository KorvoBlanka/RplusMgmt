package RplusMgmt::Controller::Export::Zipal;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media::Manager;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Option::Manager;
use Rplus::Model::Photo::Manager;
use Rplus::Model::RealtyType::Manager;
use Rplus::Model::Landmark::Manager;

use XML::Writer;
use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use File::Copy qw(move);
use File::Path qw(make_path);
use File::Basename;
use DateTime;
use JSON;
use URI;

my $config;

my $company_name = '';
my $contact_phone = '';
my $agent_phone = 0;
my $contact_name = '';
my $contact_email = '';


my %additional_fileds_by_type = (
    apartments => [],
    rooms => [],
    houses => [],
    lands => [],
    garages => [],
    commercials => [],
);

my %additional_fileds_by_offer = (
    sale => [],
    rent => [
        'LeaseType',
        'LeaseBeds',
        'LeaseSleepingPlaces',
        'LeaseMultimedia',
        'LeaseAppliances',
        'LeaseComfort',
        'LeaseAdditionally',
        'LeaseCommission',
        'LeaseCommissionSize',
        'LeaseDeposit'
    ]
);

my %fields_sub = (
# общие элементы
    Id => sub {
        my $r = shift;
        return $r->id;
    },
);

sub index {
    my $self = shift;

    $config = $self->config;

    my $acc_id = $self->session('account')->{id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'zipal', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    Mojo::IOLoop->stream($self->tx->connection)->timeout(900);

    my @sale_realty_types = split ',', $self->param('sale_realty_types');
    my @rent_realty_types = split ',', $self->param('rent_realty_types');

    my $realty_types = {
        sale => \@sale_realty_types,
        rent => \@rent_realty_types,
    };

    my $meta = from_json($media->metadata);

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $company_name = $e_opt->{'zipal-company'} ? $e_opt->{'zipal-company'} : '';
        $contact_phone = $e_opt->{'zipal-phone'} ? trim($e_opt->{'zipal-phone'}) : '';
        $agent_phone = 1 if $e_opt->{'zipal-agent-phone'};
        $contact_name = '';
        $contact_email = $e_opt->{'zipal-email'} ? $e_opt->{'zipal-email'} : '';
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;
    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    my $xml_writer = XML::Writer->new(OUTPUT => $fh, DATA_MODE => 1, DATA_INDENT => '  ');
    my $ts = localtime;
    $xml_writer->startTag('MassUploadRequest', timestamp => $ts);

    while (my ($offer_type, $value) = each $realty_types) {
        for my $realty_type (@$value) {

            my @fields;
            my @t_a = @{$additional_fileds_by_type{$realty_type}};
            push (@fields, @t_a);
            @t_a = @{$additional_fileds_by_offer{$offer_type}};
            push (@fields, @t_a);

            my $realty_category = {};
            my @tc;
            if ($realty_type =~ /apartments/) {
                push @tc, 'type.category_code' => ['apartment'];
            };

            if ($realty_type =~ /rooms/) {
                push @tc, 'type.category_code' => ['room'];
            }

            if ($realty_type =~ /houses/) {
                push @tc, 'type.category_code' => ['house'];
            }

            if ($realty_type =~ /lands/) {
                push @tc, 'type.category_code' => ['land'];
            }

            if ($realty_type =~ /commercials/) {
                push @tc, 'type.category_code' => ['commercial', 'commersial'],;
            }

            if ($realty_type =~ /garages/) {
                push @tc, type_code => 'garage';
            }

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    offer_type_code => $offer_type,
                    or => [
                            @tc,
                        ],
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'id ASC',
                require_objects => ['type', 'offer_type'],
                with_objects => ['house_type', 'balcony', 'bathroom', 'condition', 'agent',],
            );

            while(my $realty = $realty_iter->next) {

                $xml_writer->startTag('object', externalId => $realty->id, publish => "true");
                $xml_writer->startTag('common',
                  name => _build_header($realty),
                  description => $realty->description,
                  ownership => "AGENT",
                  price => $realty->price * 1000,
                  currency => "RUR",
                  square => $realty->total_square,
                  commission => $realty->agency_price - $realty->owner_price,
                  commissionType => "RUR"
                );
                $xml_writer->startTag("address");
                $xml_writer->startTag("coordinates",
                  lat => "55.962318",
                  lon => "37.525091"
                );
                $xml_writer->endTag();  # coordinates
                $xml_writer->endTag();  # address

                my @photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {
                  my $t = $config->{storage}->{external} . '/photos/' . $photo->filename;
                  $xml_writer->startTag('photos', url => $t, description => '');
                  $xml_writer->endTag();
                }

                $xml_writer->startTag('contactInfo',
                  name => $contact_name,
                  phone => $contact_phone,
                  email => $contact_email,
                  company => $company_name
                );
                $xml_writer->endTag();
                $xml_writer->endTag();  # common

                $xml_writer->startTag('specific');
                $xml_writer->endTag();

                $xml_writer->endTag();  # object
            }

        }
    }
    $xml_writer->endTag();  # req
    $xml_writer->end();
    close $fh;

    my $file_name = 'zipal_a' . $acc_id . '.xml';
    my $path = $self->config->{'storage'}->{'path'} . '/files/export/' . $file_name;
    move($file, $path);

    my $mode = 0644;
    chmod $mode, $path;

    my $url = $config->{'storage'}->{'external'} .'/files/export/' . $file_name;

    return $self->render(json => {path => $url});
}

sub _build_header {
  my $realty = shift;

  return 'HEADER';
}

1;
