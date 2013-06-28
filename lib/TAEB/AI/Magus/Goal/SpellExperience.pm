package TAEB::AI::Magus::Goal::SpellExperience;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->level > 20 }

1;

