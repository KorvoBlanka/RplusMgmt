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
    return $self->render_not_found unless $realty_id;

    my @photos;
    my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(
        query => [
            realty_pre_id => $realty_id,
            delete_date => undef,
        ],
        sort_by => 'id ASC',
    );
    while (my $photo = $photo_iter->next) {
        push @photos, {
            id => $photo->id,
            photo => $self->url_for(sprintf("/photos/%s/%s", $photo->realty_pre_id, $photo->filename)),
            thumbnail => $self->url_for(sprintf("/photos/%s/%s", $photo->realty_pre_id, $photo->thumbnail_filename)),
        };
    }

    $self->render_json(\@photos);
}

sub add {
    my $self = shift;

    return $self->render_json({status => 'failed'}) if $self->req->is_limit_exceeded;

    my $realty_id = $self->param('realty_id');
    return $self->render_not_found unless $realty_id;

    my $_save_photo = sub {
        my ($realty_pre_id, $realty_id) = @_;

        my $res = 0;
        if (my $xphoto = $self->param('photo')) {
            my $xpath = sprintf("%s/photos/%s", $self->app->static->paths->[0], $realty_pre_id);
            my $xname = (Time::HiRes::time =~ s/\.//r); # Unique name
            eval {
                make_path($xpath);
                $xphoto->move_to($xpath."/".$xname.".jpg");

                # Конвертируем изображение
                my $image = Image::Magick->new;
                $image->Read($xpath."/".$xname.".jpg");
                if ($image->Get('width') > 1920 || $image->Get('height') > 1080 || $image->Get('mime') ne 'image/jpeg') {
                    $image->Resize(geometry => '1920x1080');
                    $image->Write($xpath."/".$xname.".jpg");
                }
                $image->Resize(geometry => '320x240');
                $image->Extent(geometry => '320x240', gravity => 'Center', background => 'white');
                $image->Thumbnail(geometry => '320x240');
                $image->Write($xpath."/".$xname."_thumbnail.jpg");

                # Сохраним в БД
                my $photo = Rplus::Model::Photo->new(
                    realty_id => $realty_id,
                    realty_pre_id => $realty_pre_id,
                    filename => $xname.".jpg",
                    thumbnail_filename => $xname."_thumbnail.jpg",
                );
                $photo->save;
            } and do {
                $res = 1;
            };
        }
        return $res;
    };

    if (Rplus::Model::Realty::Manager->get_objects_count(query => [ id => $realty_id, close_date => undef ])) {
        if ($_save_photo->($realty_id, $realty_id)) {
            # Проставим время изменения объекта
            Rplus::Model::Realty::Manager->update_objects(
                set => { change_date => \'now()' },
                where => [ id => $realty_id ],
            );
            return $self->render_json({status => 'success'});
        }
    } else {
        # Очевидно, данный realty_id свободен (на нем нет недвижимости)
        # TODO: Проверка в Redis
        if ($_save_photo->($realty_id)) {
            return $self->render_json({status => 'success'});
        }
    }

    $self->render_json({status => 'failed'});
}

# Удалить фотографию
sub delete {
    my $self = shift;

    my $id = $self->param('id');
    return $self->render_not_found unless $id;

    my $photo = Rplus::Model::Photo::Manager->get_objects(query => [ id => $id, delete_date => undef ])->[0];
    return $self->render_json({status => 'failed'}) unless $photo;

    # TODO: Проверка прав доступа
    if (my $realty_id = $photo->realty_id) {
        Rplus::Model::Photo::Manager->update_objects(
            set => { delete_date => \'now()' },
            where => [ id => $photo->id ],
        );
        Rplus::Model::Realty::Manager->update_objects(
            set => { change_date => \'now()' },
            where => [ id => $photo->realty_id ],
        );
    } else {
        # Удаляется фотография не привязанная к недвижимости
        # TODO: Проверка прав доступа
        Rplus::Model::Photo::Manager->update_objects(
            set => { delete_date => \'now()' },
            where => [ id => $photo->id ],
        );
    }

    $self->render_json({status => 'success'});
}

1;
