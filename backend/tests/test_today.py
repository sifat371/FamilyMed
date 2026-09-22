from app.doses.projections import build_today


def test_today_projection_module_exists():
    assert build_today is not None
