package RplusMgmt::Banners;

use Mojo::Base 'Mojolicious::Controller';

use utf8;

use RplusWeb::Model::Banner;
use RplusWeb::Model::Banner::Manager;
use RplusWeb::Model::Setting;
use RplusWeb::Model::Setting::Manager;

use Time::HiRes;
use Image::Magick;

my $BANNERS_PATH = '/home/zak/projects/RplusWeb/public/img/banners';
my $BANNERS_URL = 'http://makler-dv.ru:3000/img/banners';

sub index {
    my $self = shift;
    $self->render;
}

#
# Ajax API
#

sub list {
    my $self = shift;

    my $banners = [];
    my $banner_iter = RplusWeb::Model::Banner::Manager->get_objects_iterator(query => [ delete_date => undef ], sort_by => 'pos');
    while (my $b = $banner_iter->next) {
        push @$banners, { map { $_ => $b->$_ } qw(id filename url) };
    }

    $self->render_json($banners);
}

sub add {
    my $self = shift;

    my $status = 'failed';
    if (!$self->req->is_limit_exceeded) {
        if (my $xbanner = $self->param('banner')) {
            my $xbanner_name = (Time::HiRes::time =~ s/\.//r); # Unique name
            eval {
                my $xbanner_file = sprintf("%s/%s.jpg", $BANNERS_PATH, $xbanner_name);
                $xbanner->move_to($xbanner_file);
                # Конвертируем изображение
                my $image = Image::Magick->new;
                $image->Read($xbanner_file);
                $image->Set(Gravity => 'Center');
                $image->Resize(geometry => '940x500');
                $image->Extent(geometry => '940x500');
                $image->Write($xbanner_file);
                1;
            } and do {
                my $banner = RplusWeb::Model::Banner->new(
                    filename => $xbanner_name.".jpg",
                    url => $BANNERS_URL."/".$xbanner_name.".jpg",
                );
                $banner->save;
                $status = 'success';
            };
        }
    } else {
        print "Limit exceeded!\n";
    }

    return $self->render_json({status => $status});
}

sub move {
    my $self = shift;

    if (my $id = $self->param('id')) {
        my $status = 'failed';
        my $direction = $self->param('direction') // '';
        my $banners = RplusWeb::Model::Banner::Manager->get_objects(query => [ delete_date => undef ], sort_by => 'pos');
        if ($#$banners == 0) {
            $status = 'success';
        } elsif ($#$banners > 0) {
            for my $i (0..$#$banners) {
                if ($banners->[$i]->id == $id) {
                    my $t = $banners->[$i]->pos;
                    my $j;
                    $j = ($i > 0 ? $i - 1 : $#$banners) if $direction eq 'left';
                    $j = ($i < $#$banners ? $i + 1 : 0) if $direction eq 'right';
                    if (defined $j) {
                        $banners->[$i]->pos($banners->[$j]->pos);
                        $banners->[$j]->pos($t);
                        $banners->[$i]->save;
                        $banners->[$j]->save;
                        $status = 'success';
                    }
                }
            }
        }
        return $self->render_json({status => $status});
    }

    $self->render_not_found;
}

sub delete {
    my $self = shift;

    if (my $id = $self->param('id')) {
        my $status = 'failed';
        if (RplusWeb::Model::Banner::Manager->update_objects(
            set => { delete_date => \"now()" },
            where => [ id => $id, delete_date => undef ]
        )) {
            $status = 'success';
        }
        return $self->render_json({status => $status});
    }

    $self->render_not_found;
}

sub get_timeout {
    my $self = shift;

    my $timeout = RplusWeb::Model::Setting->new(name => 'banner_timeout')->load()->value;

    $self->render_json({timeout => $timeout});
}

sub set_timeout {
    my $self = shift;

    if (my $timeout = $self->param('timeout')) {
        my $status = 'failed';
        $timeout = int($timeout);
        if ($timeout >= 500 && $timeout <= 9000) {
            my $x = RplusWeb::Model::Setting->new(name => 'banner_timeout')->load;
            $x->value($timeout);
            $x->save;
            $status = 'success';
        }
        return $self->render_json({status => $status});
    }

    $self->render_not_found;
}

1;
