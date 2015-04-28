package RplusMgmt::Controller::Export::IrrPartner;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use XML::Writer;
use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use File::Copy qw(move);
use File::Path qw(make_path);
use File::Basename;
use Tie::IxHash;
use JSON;
use Data::Dumper;
use URI;


my $region = 'Хабаровский край';
my $city = 'Хабаровск';

sub buildCustomFields {
    my $self = shift;
    my $realty = shift;

}


sub index {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'irr', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    Mojo::IOLoop->stream($self->tx->connection)->timeout(900);

    my @sale_realty_types = split ',', $self->param('sale_realty_types');
    my @rent_realty_types = split ',', $self->param('rent_realty_types');
    

    my $realty_types = {
        sale => \@sale_realty_types,
        rent => \@rent_realty_types,
    };

    my $irr_user_id = $self->param('irr_user_id');

    my $meta = from_json($media->metadata);
    my $contact_phones = '';
    my $agent_phone = 0;
    my $contact_name = '';
    my $contact_email = '';
    my $site_url = '';

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $contact_phones = $e_opt->{'irr-phones'} ? trim($e_opt->{'irr-phones'}) : '';
        $agent_phone = 1 if $e_opt->{'irr-agent-phone'};
        $contact_name = '';
        $contact_email = $e_opt->{'irr-email'} ? $e_opt->{'irr-email'} : '';
        $site_url = $e_opt->{'irr-url'} ? $e_opt->{'irr-url'} : '';        
    }

    #unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);



    my $xml_writer = XML::Writer->new(OUTPUT => $fh, DATA_MODE => 1, DATA_INDENT => '  ');
    $xml_writer->xmlDecl("UTF-8");

    $xml_writer->startTag('users');
    $xml_writer->startTag('user', 'deactivate-untouched' => 'false');
    $xml_writer->startTag('match');
    $xml_writer->startTag('user-id');
    $xml_writer->characters($irr_user_id);
    $xml_writer->endTag('user-id');
    $xml_writer->endTag('match');

    while (my ($offer_type, $value) = each $realty_types) {
        for my $realty_type (@$value) {

            my $realty_category = {};
            my @tc;
            if ($realty_type =~ /apartments/) {
                push @tc, ('type.category_code' => ['apartment',]);
            };

            if ($realty_type =~ /rooms/) {
                push @tc, (type_code => 'room');
            }

            if ($realty_type =~ /houses/) {
                push @tc, ('type.category_code' => ['house']);
            }

            if ($realty_type =~ /commercials/) {
                push @tc, ('type.category_code' => ['commercial', 'commersial']);
            }

            if ($realty_type =~ /lands/) {
                push @tc, ('type.category_code' => ['land']);
            }

            if ($realty_type =~ /garages/) {
                
            }

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => $offer_type,
                    or => [
                            @tc,
                        ],
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'id ASC',
                require_objects => ['type', 'offer_type'],
                with_objects => ['address_object', 'house_type', 'balcony', 'bathroom', 'condition', 'agent',],
            );

            while(my $realty = $realty_iter->next) {
                
                $xml_writer->startTag(
                    'store-ad',
                    'power-ad' => '1',
                    'source-id' => $realty->id,
                    validfrom => '2011-10-11T10:42:19',
                    validtill => '2011-10-13T10:42:19',
                    category => "/realestate/apartments-sale/new/",
                    adverttype => 'realty_new',
                );

                $xml_writer->startTag('products');
                $xml_writer->emptyTag(
                    'product',
                    name => 'premium',
                    type => '7',
                    validfrom => '2013-12-03',
                );

                $xml_writer->endTag('products');

                $xml_writer->startTag(
                    'price',
                    value => '125000',
                    currency => 'RUR',
                );
                $xml_writer->endTag('price');

                $xml_writer->startTag('title');
                $xml_writer->characters('Заголовок');
                $xml_writer->endTag('title');

                $xml_writer->startTag('description');
                $xml_writer->characters($realty->description);
                $xml_writer->endTag('description');

                $xml_writer->startTag('fotos');

                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {
                    $xml_writer->emptyTag(
                        'foto-remote',
                        url => $photo->filename,
                        #md5 => '',
                    );
                }
                $xml_writer->endTag('fotos');

                $xml_writer->startTag('custom-fields');
                #foreach (keys %$template) {
                #    my $val = $template->{$_}->($realty);
                #    next unless $val;
                #    $xml_writer->startTag($_);
                #    if($_ ne 'Images') {
                #        $xml_writer->characters($val);
                #    } else {
                #        print Dumper $val;
                #        for my $photo (@$val) {
                #            $xml_writer->startTag('Image', url => $photo);
                #            $xml_writer->endTag();
                #        }                        
                #    }
                #    $xml_writer->endTag();
                #}
                $xml_writer->endTag('custom-fields');

                $xml_writer->endTag('store-ad');
            }

        }
    }

    $xml_writer->endTag('user');
    $xml_writer->endTag('users');
    $xml_writer->end();

    close $fh;

    my $new_file = $self->config->{'storage'}->{'path'}.'/files'.$file;
    my($file_name, $dir, $ext) = fileparse($new_file);
    make_path($dir);
    move($file, $new_file);

    my $path = $self->config->{'storage'}->{'url'}.'/files'.$file;

    return $self->render(json => {path => $path});
}

1;
