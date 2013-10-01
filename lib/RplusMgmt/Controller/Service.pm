package RplusMgmt::Controller::Service;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;

use Mojo::Util qw(trim slurp);
use JSON;
use File::Temp qw(tmpnam);

sub export {
    my $self = shift;

    if (my $code = $self->param('id')) {
        if (my $media = Rplus::Model::Media::Manager->get_objects(query => [code => $code, type => 'export', delete_date => undef])->[0]) {
            my $meta = decode_json($media->metadata);

            # TODO: Fix this
            if ($media->code eq 'vnh') {
                my $offer_type_code = $self->param('offer_type_code');
                my $phones = [grep { $_ } map { trim($_) } split(/,/, scalar $self->param('phones'))];
                my $company = trim(scalar $self->param('company'));

                $meta->{'params'}->{'offer_type_code'} = $offer_type_code;
                $meta->{'params'}->{'phones'} = $phones;
                $meta->{'params'}->{'company'} = $company;

                unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
                my $file = tmpnam();
                $meta->{'prev_file'} = $file;

                $media->metadata(encode_json($meta));
                $media->save;

                system($self->app->static->paths->[0]."/../script/media/export_vnh", $file);

                $self->res->headers->content_disposition('attachment; filename=vnh.xls;');
                $self->res->content->asset(Mojo::Asset::File->new(path => $file));

                return $self->rendered(200);
            }

            # TODO: Fix this
            if ($media->code eq 'present') {
                my $offer_type_code = $self->param('offer_type_code');
                my $add_description_words = $self->param('add_description_words');
                my $phones = [grep { $_ } map { trim($_) } split(/,/, scalar $self->param('phones'))];

                $meta->{'params'}->{'offer_type_code'} = $offer_type_code;
                $meta->{'params'}->{'add_description_words'} = $add_description_words;
                $meta->{'params'}->{'phones'} = $phones;

                unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
                my $file = tmpnam();
                $meta->{'prev_file'} = $file;

                $media->metadata(encode_json($meta));
                $media->save;

                system($self->app->static->paths->[0]."/../script/media/export_present", $file);

                $self->res->headers->content_disposition('attachment; filename=present.rtf;');
                $self->res->content->asset(Mojo::Asset::File->new(path => $file));

                return $self->rendered(200);
            }

        }

        return $self->render(text => 'Not found');
    }

    return $self->render(template => 'service/export');
}

1;
