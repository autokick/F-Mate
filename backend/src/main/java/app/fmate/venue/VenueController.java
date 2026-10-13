package app.fmate.venue;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

/** 비로그인도 조회 가능한 구장 API */
@RestController
@RequestMapping("/api/v1")
public class VenueController {

    private final VenueService venues;

    public VenueController(VenueService venues) {
        this.venues = venues;
    }

    @GetMapping("/venues")
    public VenueService.Page<VenueService.VenueCard> search(
            @RequestParam(required = false) String q,
            @RequestParam(required = false) List<String> regions,
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lng,
            @RequestParam(required = false) Double radiusKm,
            @RequestParam(required = false) Boolean indoor,
            @RequestParam(required = false) String size,
            @RequestParam(required = false) List<String> facilities,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(required = false) Integer fromHour,
            @RequestParam(required = false) Integer toHour,
            @RequestParam(required = false) Integer minPrice,
            @RequestParam(required = false) Integer maxPrice,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int pageSize) {
        return venues.search(new VenueService.SearchQuery(q, regions, lat, lng, radiusKm, indoor, size, facilities,
                date, fromHour, toHour, minPrice, maxPrice, page, pageSize));
    }

    @GetMapping("/venues/{id}")
    public VenueService.VenueDetail detail(@PathVariable long id) {
        return venues.detail(id, false);
    }

    @GetMapping("/venues/{id}/availability")
    public List<VenueService.CourtAvailability> availability(
            @PathVariable long id, @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        return venues.availability(id, date);
    }

    @GetMapping("/facilities")
    public List<VenueService.Facility> facilities() {
        return venues.facilities();
    }
}
