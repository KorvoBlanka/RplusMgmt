package RplusMgmt::Controller::API::Photo;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Time::HiRes;
use File::Path qw(make_path);
use Image::Magick;

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'realty'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $realty_id = $self->param('realty_id');
    return $self->render(json => []) unless $realty_id;

    my @photos;
    my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty_id, delete_date => undef], sort_by => 'id');
    while (my $photo = $photo_iter->next) {
        push @photos, {
            id => $photo->id,
            photo_url => $self->config->{'storage'}->{'url'}.'/photos/'.$photo->realty_id.'/'.$photo->filename,
            thumbnail_url => $self->config->{'storage'}->{'url'}.'/photos/'.$photo->realty_id.'/'.$photo->thumbnail_filename,
        };
    }

    return $self->render(json => \@photos);
}

sub add {
    my $self = shift;

    my $realty_id = $self->param('realty_id');

    return $self->render(json => {status => 'failed'}) if $self->req->is_limit_exceeded;
    return $self->render(json => {status => 'failed'}) unless $realty_id;
    return $self->render(json => {status => 'failed'}) unless Rplus::Model::Realty::Manager->get_objects_count(query => [id => $realty_id]);

    if (my $file = $self->param('files[]')) {
        my $path = $self->config->{'storage'}->{'path'}.'/photos/'.$realty_id;
        my $name = Time::HiRes::time =~ s/\.//r; # Unique name

        eval {
            make_path($path);
            $file->move_to($path.'/'.$name.'.jpg');

            # Конвертируем изображение
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

            # Сохраним в БД
            my $photo = Rplus::Model::Photo->new(
                realty_id => $realty_id,
                filename => $name.'.jpg',
                thumbnail_filename => $name.'_thumbnail.jpg',
            );
            $photo->save;
        } or do {
            return $self->render(json => {status => 'failed'});
        };

        # Проставим время изменения объекта недвижимости
        Rplus::Model::Realty::Manager->update_objects(
            set => {change_date => \'now()'},
            where => [id => $realty_id],
        );

        return $self->render(json => {status => 'success'});
    }

    $self->render(json => {status => 'failed'});
}

sub delete {
    my $self = shift;

    my $id = $self->param('id');

    my $photo = Rplus::Model::Photo::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {status => 'failed'}) unless $photo;

    # TODO: Проверка прав доступа

    Rplus::Model::Photo::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $photo->id],
    );

    Rplus::Model::Realty::Manager->update_objects(
        set => {change_date => \'now()'},
        where => [id => $photo->realty_id],
    );

    $self->render(json => {status => 'success'});
}

1;
